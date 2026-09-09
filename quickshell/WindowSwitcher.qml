import QtQuick
import Quickshell
import Quickshell.Hyprland

// Alt-tab picker: lists EVERY open window across all workspaces and monitors,
// and focuses the one you choose. Modelled on PowerMenu.qml -- same Item +
// `active` + `dismissed()` shape, same Esc `Shortcut`, same click-outside
// MouseArea, same Theme tokens -- and hosted by the same Variants/PanelWindow
// pattern in shell.qml. Copying that structure is deliberate, not laziness.
//
// The old `$mod, Tab, cyclenext` blind cycle is intentionally left alone, so a
// broken switcher can never leave the session unable to change windows.
Item {
	id: root

	// Keys.onReleased below needs ACTIVE focus. The Shortcut blocks never did,
	// which is why the overlay appeared to "receive keys" without this line --
	// their working proves nothing about focus.
	focus: true

	property bool active: false

	// True once an Alt+Tab / Alt+Shift+Tab has arrived over IPC during this
	// open. Set in request() and nowhere else, so the mouse-browse `toggle`
	// path never arms and a stray Alt tap while browsing does nothing.
	property bool armed: false

	signal dismissed()

	// Snapshot of the window list, rebuilt when the overlay opens and again
	// whenever Hyprland's model actually changes while it is open.
	//
	// It is a snapshot rather than a direct binding so that a title changing
	// as a page loads cannot reorder rows under the keyboard. It still has to
	// react to `valuesChanged`, because `refreshToplevels()` is ASYNCHRONOUS:
	// reading `Hyprland.toplevels.values` on the line after the refresh call
	// returns an EMPTY list on the first open after the bar starts (measured
	// on Tawa 2026-09-06 -- a synchronous read gave 0 windows where the live
	// session had 3). Selection is preserved by address across rebuilds, so a
	// late-arriving population cannot move the highlight either.
	property var windows: []
	property int currentIndex: 0

	// Steps requested by the Alt+Tab bind while there is nothing to step
	// through yet -- the overlay is not active, or the async population above
	// has not landed. Banked here and applied by rebuild() so a fast second
	// press right after opening is never silently dropped.
	property int pendingSteps: 0

	// A commit that arrived while the asynchronous population was still in
	// flight -- the quick Alt+Tab tap, where Alt is released within a few tens
	// of milliseconds. Applied by rebuild() AFTER the banked steps, so the tap
	// lands on the previous window rather than on nothing.
	property bool pendingCommit: false

	// Warm the Hyprland connection at startup so the first Alt+Tab of a
	// session has data ready rather than an empty card.
	Component.onCompleted: Hyprland.refreshToplevels()

	Connections {
		target: Hyprland.toplevels

		function onValuesChanged(): void {
			if (root.active)
				root.rebuild();
		}
	}

	onActiveChanged: {
		if (root.active) {
			root.rebuild();
			root.forceActiveFocus();
		} else {
			root.windows = [];
			// Never let anything banked against this open leak into the next one.
			root.pendingSteps = 0;
			root.pendingCommit = false;
			root.armed = false;
		}
	}

	// Quickshell reports HyprlandToplevel.address WITHOUT the `0x` prefix
	// (`650ff5f0d460`), while hyprctl prints it WITH one (`0x650ff5f0d460`)
	// and Hyprland's `address:` matcher expects the hyprctl form. Verified on
	// Tawa 2026-09-06 against a live three-window session. Concatenating the
	// raw property into a dispatch string builds a malformed request that
	// silently focuses nothing.
	function normalizeAddress(addr: string): string {
		if (!addr)
			return "";
		return addr.indexOf("0x") === 0 ? addr : "0x" + addr;
	}

	// A window's label. Neither field alone is reliable: Pixel Composer's
	// popups carry an empty WM_CLASS and share the main window's title, so
	// each has to be able to cover for the other.
	function labelFor(entry: var): string {
		if (entry.title && entry.title.length > 0)
			return entry.title;
		if (entry.cls && entry.cls.length > 0)
			return entry.cls;
		return "(untitled window)";
	}

	// Monitor rectangles in HYPRLAND's coordinate space, which is the space
	// toplevel `at`/`size` are reported in.
	//
	// The trap this exists for: `Hyprland.monitors` reports width/height
	// PRE-transform, so a 90/270-rotated output actually occupies
	// height x width. Measured on Tawa: DP-1 is x=4000 w=2560 h=1440
	// transform=1, but really spans x in [4000, 5440] -- using the raw width
	// invents 1120px of desktop that is not there, and a window parked in
	// that phantom strip would be judged on-screen while being invisible.
	//
	// `Quickshell.screens` has the post-transform dimensions but NOT
	// Hyprland's coordinate space, so it cannot be used here.
	function monitorRects(): var {
		Hyprland.refreshMonitors();
		const mons = Hyprland.monitors ? Hyprland.monitors.values : [];
		const rects = [];
		for (let i = 0; i < mons.length; ++i) {
			const m = mons[i].lastIpcObject || ({});
			const x = m["x"], y = m["y"], w = m["width"], h = m["height"];
			// A monitor list that is empty or still reporting zeros is a
			// TRANSIENT state after refreshMonitors(), not a desktop with no
			// outputs. Skipping such entries -- and flagging nothing when
			// none survive -- is what keeps a slow refresh from declaring
			// every window offscreen.
			if (typeof x !== "number" || typeof y !== "number"
				|| typeof w !== "number" || typeof h !== "number"
				|| w <= 0 || h <= 0)
				continue;
			const rotated = m["transform"] === 1 || m["transform"] === 3
				|| m["transform"] === 5 || m["transform"] === 7;
			rects.push({
				x: x,
				y: y,
				w: rotated ? h : w,
				h: rotated ? w : h,
				focused: m["focused"] === true
			});
		}
		return rects;
	}

	function focusedRect(rects: var): var {
		for (let i = 0; i < rects.length; ++i) {
			if (rects[i].focused)
				return rects[i];
		}
		return rects.length > 0 ? rects[0] : null;
	}

	// True only when the window rectangle intersects NO monitor at all.
	//
	// A real intersection test, deliberately not a centre-point one: a window
	// hanging half off the left edge is still grabbable and must not be
	// flagged. With no usable monitor data this returns false -- rescue is
	// simply unavailable, which is safer than flagging everything.
	function isOffscreen(at: var, size: var, rects: var): bool {
		if (!rects || rects.length === 0 || !at || !size)
			return false;
		if (at.length < 2 || size.length < 2)
			return false;
		const wx = at[0], wy = at[1], ww = size[0], wh = size[1];
		if (typeof wx !== "number" || typeof wy !== "number"
			|| typeof ww !== "number" || typeof wh !== "number")
			return false;
		for (let i = 0; i < rects.length; ++i) {
			const r = rects[i];
			if (wx < r.x + r.w && wx + ww > r.x && wy < r.y + r.h && wy + wh > r.y)
				return false;
		}
		return true;
	}

	function rebuild(): void {
		Hyprland.refreshToplevels();
		const rects = root.monitorRects();

		// Remember the highlighted window so an async repopulation, or a
		// window closing while the list is open, does not move the selection.
		const previousAddress = (root.currentIndex >= 0 && root.currentIndex < root.windows.length)
			? root.windows[root.currentIndex].address
			: "";
		const hadWindows = root.windows.length > 0;

		const values = Hyprland.toplevels ? Hyprland.toplevels.values : [];
		const list = [];
		let haveFocusHistory = values.length > 0;

		for (let i = 0; i < values.length; ++i) {
			const t = values[i];
			const ipc = t.lastIpcObject || ({});
			const fh = ipc["focusHistoryID"];
			if (typeof fh !== "number")
				haveFocusHistory = false;

			list.push({
				address: root.normalizeAddress(t.address),
				title: t.title || "",
				cls: ipc["class"] || "",
				workspace: t.workspace ? t.workspace.name : "",
				monitor: t.monitor ? t.monitor.name : "",
				focusHistory: typeof fh === "number" ? fh : -1,
				// HyprlandToplevel has no x/y/width/height in Quickshell
				// 0.3.0 -- those are HyprlandMonitor properties. Geometry is
				// only reachable through lastIpcObject, as two-element arrays.
				offscreen: root.isOffscreen(ipc["at"], ipc["size"], rects)
			});
		}

		// Most-recently-focused first. `focusHistoryID` is 0 for the currently
		// focused window and counts upward; HyprlandToplevel.activated is NOT
		// usable for this (it read false for every window on a live session).
		// When any window lacks the field, keep Hyprland.toplevels' own order
		// rather than inventing a sort out of a partial signal.
		if (haveFocusHistory)
			list.sort((a, b) => a.focusHistory - b.focusHistory);

		root.windows = list;

		if (hadWindows && previousAddress) {
			for (let j = 0; j < list.length; ++j) {
				if (list[j].address === previousAddress) {
					root.currentIndex = j;
					return;
				}
			}
			// The highlighted window is gone; stay in range.
			root.currentIndex = Math.max(0, Math.min(root.currentIndex, list.length - 1));
			return;
		}

		// Opening fresh. Entry 0 is the window already focused, so counting
		// from it is what makes Alt+Tab land on the PREVIOUS window and keeps
		// Return from being a no-op.
		//
		// An empty rebuild must NOT consume the bank: the first rebuild after
		// an open frequently sees zero windows (async population, see above),
		// and eating the step there would drop the press that opened us.
		const n = list.length;
		if (n === 0) {
			root.currentIndex = 0;
			return;
		}
		const steps = root.pendingSteps === 0 ? 1 : root.pendingSteps;
		root.pendingSteps = 0;
		root.currentIndex = n > 1 ? ((steps % n) + n) % n : 0;

		// Below the empty-list guard and below the step application on
		// purpose: an empty rebuild must keep the bank (exactly like
		// pendingSteps), and the tap has to commit the row the steps chose.
		if (root.pendingCommit) {
			root.pendingCommit = false;
			root.activateCurrent();
		}
	}

	function step(delta: int): void {
		const n = root.windows.length;
		if (n === 0)
			return;
		root.currentIndex = ((root.currentIndex + delta) % n + n) % n;
	}

	// Entry point for the Hyprland bind. Hyprland consumes a matched `exec`
	// bind before the overlay's exclusive-focus surface ever sees the key, so
	// repeated Alt+Tab presses arrive here over IPC rather than through the
	// Shortcut blocks below -- those only fire when Alt is NOT held.
	//
	// This is also the ONLY place `armed` is set, which is what makes the
	// Alt-release commit fire for a real Alt+Tab and stay inert for a
	// mouse-browse opened with `toggle`.
	function request(delta: int): void {
		root.armed = true;
		console.log("switcher: request delta=" + delta + " active=" + root.active
			+ " windows=" + root.windows.length + " t=" + Date.now());
		if (root.active && root.windows.length > 0)
			root.step(delta);
		else
			root.pendingSteps += delta;
	}

	// Entry point for the QML Alt-release handler above, and for the `commit`
	// IPC (tooling and tests). Banks ONLY while active: an inactive overlay
	// must never carry a commit into its next open, and a release that beats
	// the window list is applied by rebuild() once the list arrives.
	function requestCommit(): void {
		if (!root.active)
			return;
		if (root.windows.length > 0)
			root.activateCurrent();
		else
			root.pendingCommit = true;
	}

	function activateCurrent(): void {
		const entry = root.windows[root.currentIndex];
		root.dismissed();
		if (!entry || !entry.address)
			return;
		// Explicit dispatch rather than the Wayland handle's activate(): this
		// is the same call path an offscreen-rescue follow-up needs, and it
		// shows up in hyprctl logs. HyprlandToplevel itself has no activate()
		// in Quickshell 0.3.0 -- that method is on HyprlandWorkspace.
		Hyprland.dispatch("focuswindow address:" + entry.address);
	}

	// Move an offscreen window back onto the focused monitor, then focus it,
	// so rescuing and switching to it are one action.
	//
	// `movewindowpixel` ONLY. It does not touch floating state, and that is
	// the entire reason it is used: making Hyprland 0.55.4 re-tile a floating
	// window segfaulted the compositor and destroyed a session on 2026-09-06
	// (dragBegin -> dragEnd -> changeFloatingMode -> CDwindleAlgorithm::addTarget).
	function rescueCurrent(): void {
		const entry = root.windows[root.currentIndex];
		if (!entry || !entry.address || !entry.offscreen)
			return;
		const target = root.focusedRect(root.monitorRects());
		if (!target)
			return;
		// Inset rather than placed at the origin, so the window lands well
		// inside the output instead of flush against its edge.
		const x = Math.round(target.x + target.w * 0.1);
		const y = Math.round(target.y + target.h * 0.1);
		Hyprland.dispatch("movewindowpixel exact " + x + " " + y + ",address:" + entry.address);
		root.dismissed();
		Hyprland.dispatch("focuswindow address:" + entry.address);
	}

	// Letting go of Alt commits the highlighted row. Hyprland forwards a key
	// release iff its press was forwarded (0.55.4 KeybindManager.cpp
	// onKeyEvent), and a bare Alt press matches no bind, so the Alt key-up
	// reaches whichever surface holds focus at release time -- this overlay,
	// once it has exclusive focus. Tab's press IS consumed by the ALT+Tab
	// bind, so Tab's release never arrives, which is why steps still come
	// back over IPC.
	//
	// A Hyprland `bindr` on Alt cannot do this: measured dead on Tawa
	// 2026-09-06 in every arrangement (root map, inside a submap, and with no
	// submap at all) because Alt took part in the Alt+Tab bind. See PR #228.
	//
	// Measured here 2026-09-07 across 4 controlled gestures plus 11 earlier
	// ones: the release arrives with activeFocus=true, at 17 ms after the
	// keypress for the fastest tap and 1348 ms for a deliberate hold. The
	// quick-tap gap the plan feared (release beating the surface's focus)
	// did not occur at 17 ms; if it ever does, the overlay simply stays open
	// on the correct row and Return, a click, or another Alt+Tab finishes it.
	//
	// `armed` is what keeps mouse-browse honest: only request() sets it, so
	// an Alt tap while browsing via `toggle` is inert (verified: armed=false).
	Keys.onReleased: event => {
		if (event.key !== Qt.Key_Alt)
			return;
		console.log("switcher: Alt released armed=" + root.armed
			+ " windows=" + root.windows.length
			+ " activeFocus=" + root.activeFocus
			+ " t=" + Date.now());
		if (!root.armed)
			return;
		event.accepted = true;
		root.requestCommit();
	}

	Shortcut {
		enabled: root.active
		sequence: "Esc"
		onActivated: root.dismissed()
	}

	Shortcut {
		enabled: root.active
		sequences: ["Tab", "Down", "Right"]
		onActivated: root.step(1)
	}

	Shortcut {
		enabled: root.active
		sequences: ["Shift+Tab", "Up", "Left"]
		onActivated: root.step(-1)
	}

	Shortcut {
		enabled: root.active
		sequences: ["Return", "Enter"]
		onActivated: root.activateCurrent()
	}

	// Rescue is inert on any row not flagged offscreen, so Ctrl+Return can
	// never displace a window that was reachable to begin with.
	Shortcut {
		enabled: root.active
		sequences: ["Ctrl+Return", "Ctrl+Enter"]
		onActivated: root.rescueCurrent()
	}

	Rectangle {
		anchors.fill: parent
		color: Theme.bg
		opacity: 0.55
	}

	MouseArea {
		anchors.fill: parent
		onClicked: root.dismissed()
	}

	Rectangle {
		id: card

		readonly property int rowHeight: 46

		width: Math.min(parent.width * 0.6, 760)
		height: Math.min(list.contentHeight + 24, parent.height * 0.7, 24 + rowHeight * 12)
		radius: 12
		color: Theme.depth
		border.width: 1
		border.color: Theme.border
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.verticalCenter: parent.verticalCenter

		// Swallow clicks on the card so they do not reach the dismiss handler.
		MouseArea {
			anchors.fill: parent
			onClicked: {}
		}

		Text {
			id: emptyLabel
			visible: root.windows.length === 0
			anchors.centerIn: parent
			text: "No open windows"
			color: Theme.muted
			font.pixelSize: 13
		}

		ListView {
			id: list
			anchors.fill: parent
			anchors.margins: 12
			visible: root.windows.length > 0
			clip: true
			interactive: true
			model: root.windows
			currentIndex: root.currentIndex
			highlightMoveDuration: 0
			// Keep the highlighted row on screen when the list is longer than
			// the card, so keyboard navigation cannot walk out of view.
			onCurrentIndexChanged: list.positionViewAtIndex(list.currentIndex, ListView.Contain)

			delegate: Item {
				required property var modelData
				required property int index

				width: ListView.view.width
				height: card.rowHeight

				Rectangle {
					anchors.fill: parent
					anchors.margins: 2
					radius: 8
					color: index === root.currentIndex ? Theme.accent : "transparent"
					opacity: index === root.currentIndex ? 0.22 : 1
				}

				Rectangle {
					visible: index === root.currentIndex
					width: 3
					radius: 2
					height: parent.height - 14
					anchors.left: parent.left
					anchors.leftMargin: 2
					anchors.verticalCenter: parent.verticalCenter
					color: Theme.accent
				}

				Text {
					id: titleText
					anchors.left: parent.left
					anchors.leftMargin: 16
					anchors.right: metaText.left
					anchors.rightMargin: 12
					anchors.verticalCenter: parent.verticalCenter
					elide: Text.ElideRight
					text: root.labelFor(modelData)
					color: index === root.currentIndex ? Theme.bright : Theme.text
					font.pixelSize: 13
				}

				Text {
					id: metaText
					anchors.right: parent.right
					anchors.rightMargin: 16
					anchors.verticalCenter: parent.verticalCenter
					// The hint shows ONLY on the selected offscreen row, so the
					// overlay stays quiet in the ordinary case. A rescued
					// window's workspace/monitor is not useful information
					// while it is unreachable, so it is replaced rather than
					// appended.
					text: modelData.offscreen
						? (index === root.currentIndex
							? "offscreen  ·  Ctrl+Return to rescue"
							: "offscreen")
						: ((modelData.workspace ? "ws " + modelData.workspace : "")
							+ (modelData.monitor ? "  ·  " + modelData.monitor : ""))
					color: modelData.offscreen ? Theme.error : Theme.muted
					font.pixelSize: 11
				}

				MouseArea {
					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onEntered: root.currentIndex = index
					onClicked: {
						root.currentIndex = index;
						root.activateCurrent();
					}
				}
			}
		}
	}
}

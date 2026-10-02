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

	// Last monitor rectangles that were actually usable. refreshMonitors() is
	// asynchronous and the model reads back empty or all-zero for a while
	// after it is called, so recomputing from scratch on every rebuild would
	// intermittently yield no rectangles at all -- and with no rectangles
	// nothing can be judged offscreen. Monitors change far more rarely than
	// windows do, so the previous good answer is the right fallback.
	property var monitorRectsCache: []

	// Live preview state. The preview is a REVEAL, never a focus: while this
	// overlay holds exclusive keyboard focus Hyprland 0.55.4 refuses every
	// window focus (FocusState.cpp:107-110 rawWindowFocus), and the overlay
	// must keep that exclusivity to receive the Alt release. So stepping
	// switches the highlighted window's workspace in on its own monitor and
	// raises it if floating; keyboard focus and Hyprland's focus history are
	// untouched until the commit focuses exactly once.
	//
	// monitorSnapshot: name -> { workspaceId, focused }, taken at open.
	// flippedMonitors: name -> ORIGINAL workspace id, only monitors the
	// preview actually changed. currentWorkspaceByMonitor: what we last
	// dispatched per monitor -- Hyprland.dispatch() does not update
	// Quickshell's model, so re-reading Hyprland.monitors after a flip would
	// return the pre-flip workspace.
	property var monitorSnapshot: ({})
	property string focusedMonitorAtOpen: ""
	property var flippedMonitors: ({})
	property var currentWorkspaceByMonitor: ({})
	property string previewedAddress: ""
	// Set by activateCurrent() so the inactive branch of onActiveChanged does
	// not undo the target monitor's reveal on the way out.
	property bool committing: false

	// Warm the Hyprland connection at startup so the first Alt+Tab of a
	// session has data ready rather than an empty card. Monitors are warmed
	// for the same reason: the offscreen test needs them on the FIRST open.
	Component.onCompleted: {
		Hyprland.refreshToplevels();
		Hyprland.refreshMonitors();
	}

	// A window that MOVED does not change the set of windows, so
	// Hyprland.toplevels can emit no valuesChanged at all even though every
	// coordinate this overlay reads is now stale. Rebuilding once shortly
	// after opening is what makes the first Alt+Tab agree with the second.
	//
	// Observed 2026-09-09: a window parked outside every monitor showed as
	// on-screen and unflagged on the first open, correct on the second, and
	// selecting it in the stale state focused a window nobody could see --
	// which also drags the cursor off to the screen edge.
	//
	// rebuild() preserves the selection by address and does not re-apply
	// banked steps once the list is populated, so this cannot move the
	// highlight under the user.
	Timer {
		id: settleTimer
		interval: 120
		repeat: true
		property int fires: 0
		onTriggered: {
			settleTimer.fires += 1;
			if (root.active)
				root.rebuild();
			// Three ticks rather than one: a single 120 ms settle was enough
			// on this machine but there is no guarantee the refresh has landed
			// by then, and the cost of an extra rebuild on an open overlay is
			// a list rebuild that preserves selection.
			if (settleTimer.fires >= 3 || !root.active)
				settleTimer.stop();
		}
	}

	Connections {
		target: Hyprland.toplevels

		function onValuesChanged(): void {
			if (root.active)
				root.rebuild();
		}
	}

	// Debounce so the quick Alt+Tab tap (commit 17 ms after the press) never
	// previews at all, and a held Tab does not flip a workspace per repeat.
	Timer {
		id: previewTimer
		interval: 70
		repeat: false
		onTriggered: {
			if (root.active)
				root.previewCurrent();
		}
	}

	onCurrentIndexChanged: {
		if (root.active)
			previewTimer.restart();
	}

	onActiveChanged: {
		if (root.active) {
			Hyprland.refreshMonitors();
			// Before rebuild(), so the snapshot predates any preview.
			root.snapshotMonitors();
			root.flippedMonitors = ({});
			root.previewedAddress = "";
			root.committing = false;
			root.rebuild();
			root.forceActiveFocus();
			settleTimer.fires = 0;
			settleTimer.restart();
			// currentIndex may already equal the row rebuild() chose, in which
			// case no change signal arrives to start the preview.
			previewTimer.restart();
		} else {
			// A late tick must never flip a workspace after the overlay is gone.
			previewTimer.stop();
			// The IPC dismiss paths close us without going through cancel(),
			// so the restore has to live here too. A commit keeps the target
			// monitor's reveal; it restored the others itself.
			if (!root.committing)
				root.restoreMonitors("");
			root.committing = false;
			root.flippedMonitors = ({});
			root.previewedAddress = "";
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
		// Transiently empty is normal right after refreshMonitors(); fall back
		// to the last good answer rather than reporting "no monitors", which
		// would silently disable the offscreen flag entirely.
		if (rects.length === 0)
			return root.monitorRectsCache;
		root.monitorRectsCache = rects;
		return rects;
	}

	// Per-monitor active workspace and focus at open, from the same
	// lastIpcObject read monitorRects() uses. A transiently empty model keeps
	// the previous snapshot rather than an empty one (same rule as
	// monitorRectsCache).
	function snapshotMonitors(): void {
		const mons = Hyprland.monitors ? Hyprland.monitors.values : [];
		const snap = {};
		let focused = "";
		let count = 0;
		for (let i = 0; i < mons.length; ++i) {
			const m = mons[i].lastIpcObject || ({});
			const ws = m["activeWorkspace"];
			if (typeof m["name"] !== "string" || !ws || typeof ws["id"] !== "number")
				continue;
			snap[m["name"]] = { workspaceId: ws["id"], focused: m["focused"] === true };
			if (m["focused"] === true)
				focused = m["name"];
			count += 1;
		}
		if (count === 0)
			return;
		root.monitorSnapshot = snap;
		root.focusedMonitorAtOpen = focused;
		const cur = {};
		for (const name in snap)
			cur[name] = snap[name].workspaceId;
		root.currentWorkspaceByMonitor = cur;
	}

	// Reveal the highlighted row beneath the overlay. Special workspaces
	// (id < 0) and offscreen rows get no preview: there is nothing visible to
	// reveal, and rescue stays a commit-time action.
	function previewCurrent(): void {
		const entry = root.windows[root.currentIndex];
		if (!entry || !entry.address || entry.address === root.previewedAddress)
			return;
		if (entry.offscreen || entry.workspaceId < 0)
			return;
		root.previewedAddress = entry.address;
		const mon = entry.monitor;
		const cur = root.currentWorkspaceByMonitor;
		if (mon && typeof cur[mon] === "number" && cur[mon] !== entry.workspaceId) {
			const flipped = root.flippedMonitors;
			if (!(mon in flipped))
				flipped[mon] = root.monitorSnapshot[mon].workspaceId;
			root.flippedMonitors = flipped;
			cur[mon] = entry.workspaceId;
			root.currentWorkspaceByMonitor = cur;
			Hyprland.dispatch("workspace " + entry.workspaceId);
		}
		if (entry.floating)
			Hyprland.dispatch("alterzorder top,address:" + entry.address);
		console.log("switcher: preview " + entry.address + " ws=" + entry.workspaceId
			+ " mon=" + mon + " t=" + Date.now());
	}

	// Put back every monitor the preview flipped, except `exceptMonitor`.
	// `workspace <id>` also focuses the owner monitor, so the monitor that was
	// focused at open goes LAST and focus ends where it started. Z-order is not
	// restored -- no dispatcher can -- so a raised floating window stays raised.
	function restoreMonitors(exceptMonitor: string): void {
		const flipped = root.flippedMonitors;
		const cur = root.currentWorkspaceByMonitor;
		const focusedName = root.focusedMonitorAtOpen;
		let restoredAny = false;
		let restoredFocused = false;
		const names = Object.keys(flipped).filter(n => n !== exceptMonitor);
		names.sort((a, b) => (a === focusedName ? 1 : 0) - (b === focusedName ? 1 : 0));
		for (let i = 0; i < names.length; ++i) {
			const name = names[i];
			Hyprland.dispatch("workspace " + flipped[name]);
			cur[name] = flipped[name];
			restoredAny = true;
			if (name === focusedName)
				restoredFocused = true;
		}
		const kept = {};
		if (exceptMonitor && exceptMonitor in flipped)
			kept[exceptMonitor] = flipped[exceptMonitor];
		root.flippedMonitors = kept;
		root.currentWorkspaceByMonitor = cur;
		// Monitor focus follows the last workspace dispatch; on a cancel, hand
		// it back explicitly when the focused-at-open monitor was not flipped.
		// The window focus this attempts is refused while the overlay is up.
		if (!exceptMonitor && restoredAny && !restoredFocused && focusedName)
			Hyprland.dispatch("focusmonitor " + focusedName);
	}

	// Esc and click-outside go through here. Alt+Esc and the IPC dismiss paths
	// close the overlay directly and restore in onActiveChanged instead.
	function cancel(): void {
		previewTimer.stop();
		root.restoreMonitors("");
		root.dismissed();
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
				// Preview and commit-warp inputs. workspaceId < 0 is a special
				// workspace (or unknown) and is never previewed.
				workspaceId: (ipc["workspace"] && typeof ipc["workspace"]["id"] === "number") ? ipc["workspace"]["id"] : -1,
				floating: ipc["floating"] === true,
				at: ipc["at"],
				size: ipc["size"],
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
		previewTimer.stop();
		root.committing = true;
		// Every flipped monitor except the target's goes back; the target's
		// stays revealed so the screen being looked at does not flip away and
		// back.
		root.restoreMonitors(entry ? entry.monitor : "");
		// Where the cursor has to end up. Offscreen rows are overridden below
		// with the rescue position.
		let warp = root.centreOf(entry ? entry.at : null, entry ? entry.size : null);
		root.dismissed();
		if (!entry || !entry.address)
			return;
		// An offscreen window is rescued as PART of being selected, never
		// behind a second keybind. Two reasons, the first found by testing on
		// 2026-09-09:
		//
		// 1. This overlay only exists while Alt is held. Reaching any chord
		//    means letting go of Alt, which already commits and dismisses --
		//    and with Alt still down the event carries Alt, so a Shortcut
		//    declared "Ctrl+Return" does not match it. A secondary bind is
		//    therefore reachable only via the mouse-browse `toggle` path,
		//    which is exactly when it is not needed.
		// 2. Focusing a window that sits outside every monitor without moving
		//    it is a no-op the user cannot see. Selecting it can only sensibly
		//    mean "bring it back".
		if (root.isAddressOffscreen(entry.address, entry.offscreen)) {
			const p = root.rescueToAddress(entry.address);
			warp = p ? root.centreOf([p.x, p.y], entry.size) : null;
		}
		// ...and check again once a refresh has actually landed. Neither the
		// snapshot nor the live read above can be trusted for a very fast
		// commit: Hyprland.dispatch() does not update Quickshell's model, so
		// a window moved moments ago still reports its OLD coordinates, and
		// the fastest measured Alt tap on this machine committed 17 ms after
		// the keypress. Without this, such a commit focuses a window the user
		// cannot see and drags the cursor off to the screen edge -- observed
		// on 2026-09-09.
		Hyprland.refreshToplevels();
		root.pendingRescueAddress = entry.address;
		rescueCheckTimer.restart();
		// Warp the cursor into the target BEFORE the focus. When the overlay
		// unmaps, Hyprland refocuses the window under the cursor
		// (LayerSurface.cpp onUnmap -> refocusLastWindow -> mouseMoveUnified)
		// before focuswindow arrives; after a preview that is a bystander,
		// which would land in the focus history ahead of the target. It is
		// where focuswindow's own warpCursor() puts the cursor anyway.
		if (warp)
			Hyprland.dispatch("movecursor " + warp.x + " " + warp.y);
		// Focus happens only here, never during the preview: Hyprland refuses
		// a window focus while this overlay holds exclusive keyboard focus
		// (FocusState.cpp:107-110), so the preview reveals and the commit
		// focuses. HyprlandToplevel has no activate() in Quickshell 0.3.0.
		Hyprland.dispatch("focuswindow address:" + entry.address);
	}

	// Centre of an `at`/`size` pair, or null when either is not numeric.
	function centreOf(at: var, size: var): var {
		if (!at || !size || at.length < 2 || size.length < 2)
			return null;
		if (typeof at[0] !== "number" || typeof at[1] !== "number"
			|| typeof size[0] !== "number" || typeof size[1] !== "number")
			return null;
		return { x: Math.round(at[0] + size[0] / 2), y: Math.round(at[1] + size[1] / 2) };
	}

	// Live offscreen test for one address, used at commit time. Falls back to
	// the row's snapshot when the address is no longer in the model at all,
	// so a window that closed under the cursor cannot change the answer.
	function isAddressOffscreen(address: string, fallback: bool): bool {
		const vals = Hyprland.toplevels ? Hyprland.toplevels.values : [];
		for (let i = 0; i < vals.length; ++i) {
			if (root.normalizeAddress(vals[i].address) !== address)
				continue;
			const ipc = vals[i].lastIpcObject || ({});
			return root.isOffscreen(ipc["at"], ipc["size"], root.monitorRects());
		}
		return fallback;
	}

	// Set by activateCurrent(), cleared by rescueCheckTimer. Holds the address
	// whose position could not be trusted at commit time.
	property string pendingRescueAddress: ""

	Timer {
		id: rescueCheckTimer
		interval: 200
		repeat: false
		onTriggered: {
			const address = root.pendingRescueAddress;
			root.pendingRescueAddress = "";
			if (!address)
				return;
			// Fallback false: if the window is gone from the model entirely
			// there is nothing to rescue, and guessing would move whatever
			// inherited its address.
			if (root.isAddressOffscreen(address, false))
				root.rescueToAddress(address);
		}
	}

	// Move an offscreen window onto the focused monitor. Called from
	// activateCurrent() just before the focus dispatch, so the move and the
	// focus are one user action.
	//
	// `movewindowpixel` ONLY. It does not touch floating state, and that is
	// the entire reason it is used: making Hyprland 0.55.4 re-tile a floating
	// window segfaulted the compositor and destroyed a session on 2026-09-06
	// (dragBegin -> dragEnd -> changeFloatingMode -> CDwindleAlgorithm::addTarget).
	function rescueToAddress(address: string): var {
		const target = root.focusedRect(root.monitorRects());
		if (!target || !address)
			return null;
		// Inset rather than placed at the origin, so the window lands well
		// inside the output instead of flush against its edge.
		const x = Math.round(target.x + target.w * 0.1);
		const y = Math.round(target.y + target.h * 0.1);
		Hyprland.dispatch("movewindowpixel exact " + x + " " + y + ",address:" + address);
		return { x: x, y: y };
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
		onActivated: root.cancel()
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

	Rectangle {
		anchors.fill: parent
		color: Theme.bg
		opacity: 0.55
	}

	MouseArea {
		anchors.fill: parent
		onClicked: root.cancel()
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
							? "offscreen  ·  select to bring it back"
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

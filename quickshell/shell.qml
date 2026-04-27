// Quickshell: top bar (Hyprland workspaces + clock) + WlSessionLock (PAM password).
// One bar per output via `Variants` + `Quickshell.screens` (not follow-focus on a single PanelWindow).
// Lock: `quickshell ipc -p ~/.config/quickshell -n call lock activate` (see `quickshell-lock`).
// Debug: `quickshell ipc -p ~/.config/quickshell show` (subcommand is `ipc`, not a bare `show` flag).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
	id: shellRoot

	// Monitor whose horizontal center is nearest the combined desktop midpoint (typical "center" panel).
	function centerOutputScreen(): var {
		const screens = Quickshell.screens;
		const n = screens.length;
		if (n === 0)
			return null;
		if (n === 1)
			return screens[0];

		let minX = screens[0].x;
		let maxX = screens[0].x + screens[0].width;
		for (let i = 1; i < n; ++i) {
			const s = screens[i];
			minX = Math.min(minX, s.x);
			maxX = Math.max(maxX, s.x + s.width);
		}

		const mid = (minX + maxX) / 2;
		let best = screens[0];
		let bestDist = Math.abs(best.x + best.width / 2 - mid);
		for (let i = 1; i < n; ++i) {
			const s = screens[i];
			const d = Math.abs(s.x + s.width / 2 - mid);
			if (d < bestDist) {
				bestDist = d;
				best = s;
			}
		}
		return best;
	}

	LockContext {
		id: lockContext

		onUnlocked: {
			sessionLock.locked = false;
		}
	}

	WlSessionLock {
		id: sessionLock
		locked: false

		WlSessionLockSurface {
			id: lockSessionSurface
			// Full lock UI only on the center output. Children are reparented to an internal
			// contentItem, so `parent` on LockSurface is not this object — use `lockSessionSurface.showLockUi`.
			// Other outputs stay covered (protocol requirement) via `color` only.
			readonly property bool showLockUi: {
				const c = shellRoot.centerOutputScreen();
				return c && screen && c.name === screen.name;
			}

			color: "#1e1e2e"

			LockSurface {
				anchors.fill: parent
				visible: lockSessionSurface.showLockUi
				context: lockContext
			}
		}
	}

	IpcHandler {
		target: "lock"

		// Return type required or quickshell will not register this for `ipc call lock activate`.
		function activate(): void {
			sessionLock.locked = true;
		}
	}

	Variants {
		model: Quickshell.screens

		PanelWindow {
			required property var modelData

			screen: modelData

			anchors.top: true
			anchors.left: true
			anchors.right: true
			implicitHeight: 32
			color: "#1e1e2e"

			RowLayout {
				anchors.fill: parent
				anchors.leftMargin: 10
				anchors.rightMargin: 10
				spacing: 10

				Repeater {
					model: 6

					delegate: Item {
						required property int index

						property int wid: index + 1
						property bool isActive: Hyprland.focusedWorkspace?.id === wid

						implicitWidth: wsLabel.implicitWidth + 16
						implicitHeight: 32

						Text {
							id: wsLabel
							anchors.centerIn: parent
							text: parent.wid
							color: parent.isActive ? "#89b4fa" : "#6c7086"
							font.pixelSize: 14
							font.bold: true
						}

						MouseArea {
							anchors.fill: parent
							acceptedButtons: Qt.LeftButton
							onClicked: Hyprland.dispatch("workspace " + parent.wid)
						}
					}
				}

				Item {
					Layout.fillWidth: true
				}

				Text {
					id: clockLabel
					color: "#cdd6f4"
					font.pixelSize: 14

					Timer {
						running: true
						repeat: true
						interval: 30000
						onTriggered: clockLabel.text = Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm")
					}

					Component.onCompleted: clockLabel.text = Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm")
				}
			}
		}
	}
}

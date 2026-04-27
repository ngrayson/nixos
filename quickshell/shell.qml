// Quickshell: top bar (Hyprland workspaces + clock) + WlSessionLock (PAM password).
// Lock: `quickshell ipc -p ~/.config/quickshell/shell.qml -n call lock activate` (see `quickshell-lock`).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
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
			LockSurface {
				anchors.fill: parent
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

	function syncBarScreen() {
		if (!Hyprland.focusedMonitor) {
			return;
		}
		const name = Hyprland.focusedMonitor.name;
		const scr = Quickshell.screens.find(s => s.name === name);
		if (scr) {
			bar.screen = scr;
		}
	}

	PanelWindow {
		id: bar

		anchors.top: true
		anchors.left: true
		anchors.right: true
		implicitHeight: 32
		color: "#1e1e2e"

		Component.onCompleted: syncBarScreen()

		Connections {
			target: Hyprland

			function onFocusedMonitorChanged() {
				syncBarScreen();
			}
		}

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

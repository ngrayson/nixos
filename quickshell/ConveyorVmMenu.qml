import QtQuick
import Quickshell

// Conveyor Personal Compute VM menu, opened by RIGHT-clicking the VM pill
// (left-click is start / graceful stop). Same dropdown shape as ClaudeMenu:
// sizes itself via contentWidth/contentHeight, the hosting PopupWindow's
// grabbed focus handles click-outside dismissal.
//
// The status lines are NOT formatted here: shell.qml builds them once
// (conveyorVmLines) for both this menu and the hover tooltip.
//
// Every action goes through qs-conveyor-vm-ctl (home/services/
// conveyor-vm-status.nix), never conveyor-k3 or limactl directly. Force stop
// is the only path that can interrupt a running card, and it lives only here.
//
// Esc is handled with Keys on a focused item, not a Shortcut: a Shortcut inside
// a bar PopupWindow is the object whose teardown segfaulted the bar on hot
// reloads (2026-10-02 crash investigation, cancelled card).
FocusScope {
	id: root

	property bool active: false
	property var lines: []
	property string instance: ""
	property string status: ""
	// "", "starting", "stopping" or "draining".
	property string transition: ""
	// Running cards, or -1 when unknown (treated as busy).
	property int cards: -1

	signal dismissed()

	readonly property bool running: root.status === "Running"
	readonly property bool busy: root.transition !== ""
	readonly property int contentWidth: 380
	readonly property int contentHeight: cardCol.implicitHeight + 40
	implicitWidth: root.contentWidth
	implicitHeight: root.contentHeight

	onActiveChanged: {
		if (root.active) {
			root.forceActiveFocus();
			root.ctl("refresh");
		}
	}

	Keys.onEscapePressed: root.dismissed()

	function ctl(action: string): void {
		const cmd = ["qs-conveyor-vm-ctl", action];
		if (root.instance !== "")
			cmd.push("--instance=" + root.instance);
		Quickshell.execDetached(cmd);
	}

	function run(action: string): void {
		root.ctl(action);
		root.dismissed();
	}

	// Rows are filtered by state so the menu never offers something the VM
	// cannot do right now.
	readonly property var actions: [
		{ label: "Open Personal Compute panel", action: "open-panel", show: true },
		{ label: "Start", action: "start", show: !root.running && !root.busy },
		{ label: "Stop now", action: "stop", show: root.running && !root.busy && root.cards === 0 },
		{ label: "Stop when the running card finishes", action: "stop-when-idle", show: root.running && !root.busy && root.cards !== 0 },
		{ label: "Cancel pending stop", action: "cancel-stop", show: root.transition === "draining" },
		{ label: "Force stop — interrupts the running card", action: "force-stop", show: root.running && root.cards !== 0 },
		{ label: "Logs in terminal", action: "logs", show: true },
		{ label: "Refresh", action: "refresh", show: true }
	].filter(a => a.show)

	Rectangle {
		id: card
		anchors.fill: parent
		radius: 12
		color: Theme.depth
		border.width: 1
		border.color: Theme.border

		Column {
			id: cardCol
			anchors.centerIn: parent
			width: parent.width - 40
			spacing: 12

			Row {
				width: parent.width
				spacing: 10

				Text {
					anchors.verticalCenter: parent.verticalCenter
					text: String.fromCodePoint(0xF048B) // nf-md-server
					color: Theme.accent
					font.pixelSize: 18
					font.family: "IosevkaTermSlab NF"
				}

				Text {
					anchors.verticalCenter: parent.verticalCenter
					text: "Conveyor VM" + (root.instance ? " · " + root.instance : "")
					color: Theme.strong
					font.pixelSize: 14
				}
			}

			Column {
				width: parent.width
				spacing: 4

				Repeater {
					model: root.lines

					delegate: Text {
						required property var modelData

						width: cardCol.width
						elide: Text.ElideRight
						text: modelData
						color: Theme.text
						font.pixelSize: 12
					}
				}
			}

			Rectangle {
				width: parent.width
				height: 1
				color: Theme.border
			}

			Column {
				width: parent.width
				spacing: 6

				Repeater {
					model: root.actions

					delegate: Rectangle {
						required property var modelData

						width: cardCol.width
						implicitHeight: 30
						radius: 6
						color: actionHover.containsMouse ? Theme.surface : Theme.chrome
						border.width: 1
						border.color: modelData.action === "force-stop" ? Theme.error : Theme.border

						Text {
							anchors.left: parent.left
							anchors.leftMargin: 12
							anchors.verticalCenter: parent.verticalCenter
							text: modelData.label
							color: modelData.action === "force-stop" ? Theme.error : Theme.text
							font.pixelSize: 12
						}

						MouseArea {
							id: actionHover
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: root.run(modelData.action)
						}
					}
				}
			}
		}
	}
}

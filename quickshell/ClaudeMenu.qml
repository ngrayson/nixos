import QtQuick
import Quickshell
import Quickshell.Io

// Claude action menu, opened by RIGHT-clicking the Claude pill (left-click
// stays "new agent", matching the media pill's split). Rendered as a small
// dropdown anchored under the pill -- the same choice Nick made for the media
// popup -- so it sizes itself via contentWidth/contentHeight and the hosting
// PopupWindow's grabbed focus handles click-outside dismissal.
//
// The usage lines are NOT formatted here: shell.qml builds them once
// (claudeUsageLines) and passes them down, so the hover tooltip and this menu
// can never drift apart.
Item {
	id: root

	property bool active: false
	// shellRoot.claudeUsageLines() -- pre-formatted, one string per line.
	property var lines: []
	// The plan name shown beside the header glyph, e.g. "Pro".
	property string plan: ""

	signal dismissed()

	readonly property int contentWidth: 360
	readonly property int contentHeight: cardCol.implicitHeight + 40
	implicitWidth: root.contentWidth
	implicitHeight: root.contentHeight

	// Refresh on open so the numbers are current rather than up to five
	// minutes stale from the timer's last tick. The poller writes atomically,
	// so the FileView in shell.qml picks the new file up on its own.
	onActiveChanged: {
		if (root.active)
			root.refresh();
	}

	function refresh(): void {
		if (usageProc.running)
			usageProc.running = false;
		usageProc.running = true;
	}

	function launch(cmd: var): void {
		Quickshell.execDetached(cmd);
		root.dismissed();
	}

	Process {
		id: usageProc
		command: ["qs-claude-usage"]
		running: false
	}

	Shortcut {
		enabled: root.active
		sequence: "Esc"
		onActivated: root.dismissed()
	}

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
					text: String.fromCodePoint(0xF4F5) // nf-oct-north_star
					color: Theme.accent
					font.pixelSize: 18
					font.family: "IosevkaTermSlab NF"
				}

				Text {
					anchors.verticalCenter: parent.verticalCenter
					text: "Claude" + (root.plan ? " · " + root.plan : "")
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
					model: [
						{
							label: "New agent (Stellarium)",
							cmd: ["kitty", "-e", "zsh", "-lic", "agent-new"]
						},
						{
							label: "Existing agent (Stellarium)",
							cmd: ["kitty", "-e", "zsh", "-lic", "agent"]
						},
						{
							label: "Open claude.ai",
							cmd: ["xdg-open", "https://claude.ai"]
						},
						{
							label: "VS Code: ~/.config/nixos",
							cmd: ["code", Quickshell.env("HOME") + "/.config/nixos"]
						}
					]

					delegate: Rectangle {
						required property var modelData

						width: cardCol.width
						implicitHeight: 30
						radius: 6
						color: actionHover.containsMouse ? Theme.surface : Theme.chrome
						border.width: 1
						border.color: Theme.border

						Text {
							anchors.left: parent.left
							anchors.leftMargin: 12
							anchors.verticalCenter: parent.verticalCenter
							text: modelData.label
							color: Theme.text
							font.pixelSize: 12
						}

						MouseArea {
							id: actionHover
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: root.launch(modelData.cmd)
						}
					}
				}
			}
		}
	}
}

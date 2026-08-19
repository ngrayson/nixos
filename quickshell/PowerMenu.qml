import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Centered power overlay: Sleep / Hibernate (if logind allows) / Restart / Shut Down.
// Hosted in a focusable Overlay PanelWindow; Esc and click-outside dismiss.
Item {
	id: root

	property bool active: false

	signal dismissed()

	property bool hibernateAvailable: false

	onActiveChanged: {
		if (active)
			root.refreshHibernate();
	}

	function refreshHibernate(): void {
		if (hibernateQuery.running)
			hibernateQuery.running = false;
		hibernateQuery.running = true;
	}

	function requestPower(kind: string): void {
		root.dismissed();
		if (powerProc.running)
			powerProc.running = false;
		if (kind === "sleep")
			powerProc.command = ["systemctl", "suspend"];
		else if (kind === "hibernate")
			powerProc.command = ["systemctl", "hibernate"];
		else if (kind === "reboot")
			powerProc.command = ["systemctl", "reboot"];
		else if (kind === "poweroff")
			powerProc.command = ["systemctl", "poweroff"];
		else
			return;
		powerProc.running = true;
	}

	Process {
		id: hibernateQuery
		command: ["busctl", "--system", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "CanHibernate"]
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const t = this.text.trim();
				root.hibernateAvailable = t.indexOf("\"yes\"") !== -1;
			}
		}

		onExited: exitCode => {
			if (exitCode !== 0)
				root.hibernateAvailable = false;
		}
	}

	Process {
		id: powerProc
		running: false
	}

	Shortcut {
		enabled: root.active
		sequence: "Esc"
		onActivated: root.dismissed()
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
		width: actionRow.implicitWidth + 48
		height: actionRow.implicitHeight + 40
		radius: 12
		color: Theme.depth
		border.width: 1
		border.color: Theme.border
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.verticalCenter: parent.verticalCenter
		anchors.verticalCenterOffset: parent.height * 0.25

		MouseArea {
			anchors.fill: parent
			onClicked: {}
		}

		Row {
			id: actionRow
			anchors.centerIn: parent
			spacing: 28

			Repeater {
				model: [
					{
						kind: "sleep",
						label: "Sleep",
						glyph: 0xF04B2
					},
					{
						kind: "hibernate",
						label: "Hibernate",
						glyph: 0xF0717
					},
					{
						kind: "reboot",
						label: "Restart",
						glyph: 0xF0709
					},
					{
						kind: "poweroff",
						label: "Shut Down",
						glyph: 0xF0425
					}
				]

				delegate: Item {
					required property var modelData
					visible: modelData.kind !== "hibernate" || root.hibernateAvailable
					implicitWidth: visible ? Math.max(powerIcon.implicitWidth, powerLabel.implicitWidth) + 16 : 0
					implicitHeight: powerIcon.implicitHeight + powerLabel.implicitHeight + 10
					opacity: powerHover.containsMouse ? 1 : 0.85

					Text {
						id: powerIcon
						anchors.top: parent.top
						anchors.horizontalCenter: parent.horizontalCenter
						text: String.fromCodePoint(modelData.glyph)
						color: Theme.text
						font.pixelSize: 22
						font.family: "IosevkaTermSlab NF"
					}

					Text {
						id: powerLabel
						anchors.top: powerIcon.bottom
						anchors.topMargin: 6
						anchors.horizontalCenter: parent.horizontalCenter
						text: modelData.label
						color: Theme.text
						font.pixelSize: 12
					}

					MouseArea {
						id: powerHover
						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: root.requestPower(modelData.kind)
					}
				}
			}
		}
	}

	Component.onCompleted: root.refreshHibernate()
}

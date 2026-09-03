import QtQuick
import Quickshell
import Quickshell.Io

// Screen-warmth control panel, opened by right-clicking the sunset pill.
// Mirrors PowerMenu.qml: a focusable Overlay PanelWindow hosts it, Esc and
// click-outside dismiss.
//
// Every action shells out to `hypr-sunset-ctl`. This panel deliberately never
// calls `hyprctl hyprsunset` itself -- hyprsunset must have exactly one writer
// (the scheduler), or two writers fight over the colour transform matrix and
// the screen flickers between them.
Item {
	id: root

	property bool active: false
	// The scheduler's published state, passed down from shell.qml.
	property var state: ({})

	signal dismissed()

	readonly property int transitionMin: root.state?.transitionMin ?? 45
	readonly property bool suppressed: (root.state?.phase ?? "") === "off"

	function run(args: var): void {
		if (ctlProc.running)
			ctlProc.running = false;
		ctlProc.command = ["hypr-sunset-ctl"].concat(args);
		ctlProc.running = true;
	}

	function fmtClock(epoch: int): string {
		if (!epoch)
			return "--:--";
		return Qt.formatTime(new Date(epoch * 1000), "HH:mm");
	}

	Process {
		id: ctlProc
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
		width: 420
		height: cardCol.implicitHeight + 40
		radius: 12
		color: Theme.depth
		border.width: 1
		border.color: Theme.border
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.verticalCenter: parent.verticalCenter
		anchors.verticalCenterOffset: parent.height * 0.15

		MouseArea {
			anchors.fill: parent
			onClicked: {}
		}

		Column {
			id: cardCol
			anchors.centerIn: parent
			width: parent.width - 40
			spacing: 14

			Row {
				spacing: 8

				Text {
					text: String.fromCodePoint(0xF059A) // nf-md-weather_sunset
					color: Theme.accent
					font.pixelSize: 20
					font.family: "IosevkaTermSlab NF"
				}

				Text {
					text: "Screen warmth"
					color: Theme.strong
					font.pixelSize: 16
				}
			}

			// Overview. Mirrors the pill's tooltip so the two never disagree.
			Column {
				width: parent.width
				spacing: 3

				Text {
					text: root.suppressed ? "Paused" : ("Now  " + (root.state?.temp ?? "--") + "K  ·  gamma " + (root.state?.gamma ?? "--") + "%")
					color: Theme.text
					font.pixelSize: 13
				}

				Text {
					text: "Night  " + (root.state?.nightTemp ?? "--") + "K  ·  gamma " + (root.state?.nightGamma ?? "--") + "%"
					color: Theme.muted
					font.pixelSize: 13
				}

				Text {
					text: "Sunrise " + root.fmtClock(root.state?.sunrise ?? 0) + "   Sunset " + root.fmtClock(root.state?.sunset ?? 0)
					color: Theme.muted
					font.pixelSize: 13
				}

				Text {
					visible: root.suppressed && (root.state?.disabledUntil ?? 0) > 0
					text: "Resumes at " + root.fmtClock(root.state?.disabledUntil ?? 0)
					color: Theme.accent
					font.pixelSize: 13
				}
			}

			Rectangle {
				width: parent.width
				height: 1
				color: Theme.border
			}

			Text {
				text: "Disable for"
				color: Theme.strong
				font.pixelSize: 13
			}

			Row {
				spacing: 8

				Repeater {
					model: [
						{
							label: "30 min",
							args: ["disable", "1800"]
						},
						{
							label: "1 hr",
							args: ["disable", "3600"]
						},
						{
							label: "2 hr",
							args: ["disable", "7200"]
						},
						{
							label: "Til sunrise",
							args: ["disable", "sunrise"]
						}
					]

					delegate: Rectangle {
						required property var modelData
						implicitWidth: disableLabel.implicitWidth + 18
						implicitHeight: 28
						radius: 6
						color: disableHover.containsMouse ? Theme.surface : Theme.chrome
						border.width: 1
						border.color: Theme.border

						Text {
							id: disableLabel
							anchors.centerIn: parent
							text: modelData.label
							color: Theme.text
							font.pixelSize: 12
						}

						MouseArea {
							id: disableHover
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: {
								root.run(modelData.args);
								root.dismissed();
							}
						}
					}
				}
			}

			Text {
				text: "Start transition — minutes before sunset/sunrise"
				color: Theme.strong
				font.pixelSize: 13
			}

			Row {
				spacing: 8

				Repeater {
					model: [15, 30, 45, 60, 90]

					delegate: Rectangle {
						required property var modelData
						readonly property bool current: modelData === root.transitionMin
						implicitWidth: transitionLabel.implicitWidth + 18
						implicitHeight: 28
						radius: 6
						color: current ? Theme.selection : (transitionHover.containsMouse ? Theme.surface : Theme.chrome)
						border.width: 1
						border.color: current ? Theme.accent : Theme.border

						Text {
							id: transitionLabel
							anchors.centerIn: parent
							text: modelData
							color: current ? Theme.bright : Theme.text
							font.pixelSize: 12
						}

						MouseArea {
							id: transitionHover
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							// Stays open: this is a setting people compare, not
							// a one-shot action like the disable buttons.
							onClicked: root.run(["set", "transitionMin", String(modelData)])
						}
					}
				}
			}

			Rectangle {
				width: parent.width
				height: 1
				color: Theme.border
			}

			Rectangle {
				implicitWidth: toggleLabel.implicitWidth + 22
				implicitHeight: 30
				radius: 6
				color: toggleHover.containsMouse ? Theme.surface : Theme.chrome
				border.width: 1
				border.color: Theme.border

				Text {
					id: toggleLabel
					anchors.centerIn: parent
					text: (root.state?.enabled ?? true) ? "Turn off entirely" : "Turn back on"
					color: Theme.text
					font.pixelSize: 12
				}

				MouseArea {
					id: toggleHover
					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: {
						root.run(["toggle"]);
						root.dismissed();
					}
				}
			}
		}
	}
}

import QtQuick
import Quickshell

// Calendar popup, opened by clicking the clock in the top bar. Mirrors
// SunsetMenu.qml / PowerMenu.qml: a focusable Overlay PanelWindow (in
// shell.qml) hosts it on the center output, Esc and click-outside dismiss.
//
// Layout and look are modelled on EverCal (github.com/snes19xx/EverCal, MIT),
// which Nick picked as the reference: a clean borderless month grid with today
// in a filled rounded square and event days dotted, beside a day panel that
// lists that day's events as rounded cards. No code is lifted -- this is plain
// QML against this shell's Theme tokens.
//
// Events come in already-expanded (recurring occurrences included) from
// home/services/calendar-sync.nix via a JSON cache; shell.qml reads that file
// and passes the list down as `events`. Each event is
// {title, start (epoch s), end (epoch s), allDay (bool), day ("YYYY-MM-DD")}.
// The `day` string is authoritative for bucketing -- it was computed with the
// right timezone handling in the sync script, so this file never juggles tz.
Item {
	id: root

	property bool active: false
	property var events: []

	signal dismissed()

	// Displayed month + selected day. Seeded to today whenever the popup opens.
	property int viewYear: 2026
	property int viewMonth: 0 // 0-11
	property string selectedKey: ""
	readonly property string todayKey: root.keyOf(new Date())

	readonly property var weekdayLetters: ["S", "M", "T", "W", "T", "F", "S"]
	readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

	function pad2(n: int): string {
		return n < 10 ? "0" + n : "" + n;
	}

	// Calendar-day key for a JS Date, in LOCAL terms (matches the sync script's
	// day strings for timed events; all-day events already carry their plain
	// date).
	function keyOf(d: var): string {
		return d.getFullYear() + "-" + root.pad2(d.getMonth() + 1) + "-" + root.pad2(d.getDate());
	}

	function seedToday(): void {
		const now = new Date();
		root.viewYear = now.getFullYear();
		root.viewMonth = now.getMonth();
		root.selectedKey = root.keyOf(now);
	}

	function prevMonth(): void {
		if (root.viewMonth === 0) {
			root.viewMonth = 11;
			root.viewYear -= 1;
		} else {
			root.viewMonth -= 1;
		}
	}

	function nextMonth(): void {
		if (root.viewMonth === 11) {
			root.viewMonth = 0;
			root.viewYear += 1;
		} else {
			root.viewMonth += 1;
		}
	}

	// 42 cells (6 weeks), Sunday-first, starting from the Sunday on/before the
	// 1st of the displayed month. new Date() normalises day overflow for us.
	readonly property var cells: {
		const first = new Date(root.viewYear, root.viewMonth, 1);
		const start = new Date(root.viewYear, root.viewMonth, 1 - first.getDay());
		const out = [];
		for (let i = 0; i < 42; ++i) {
			const dt = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
			out.push({
				"key": root.keyOf(dt),
				"day": dt.getDate(),
				"inMonth": dt.getMonth() === root.viewMonth
			});
		}
		return out;
	}

	// day-string -> array of events, built once per events change.
	readonly property var eventsByDay: {
		const map = ({});
		const evs = root.events || [];
		for (let i = 0; i < evs.length; ++i) {
			const e = evs[i];
			if (!e || !e.day)
				continue;
			if (!map[e.day])
				map[e.day] = [];
			map[e.day].push(e);
		}
		return map;
	}

	readonly property var selectedEvents: root.eventsByDay[root.selectedKey] || []

	function selectedDate(): var {
		const p = (root.selectedKey || root.todayKey).split("-");
		return new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
	}

	function fmtTime(epoch: real): string {
		return Qt.formatTime(new Date(epoch * 1000), "h:mm AP");
	}

	function fmtRange(e: var): string {
		if (e.allDay)
			return "All day";
		return root.fmtTime(e.start) + "  –  " + root.fmtTime(e.end);
	}

	onActiveChanged: {
		if (root.active)
			root.seedToday();
	}

	Component.onCompleted: root.seedToday()

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
		width: 780
		height: 480
		radius: 16
		color: Theme.depth
		border.width: 1
		border.color: Theme.border
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.verticalCenter: parent.verticalCenter
		anchors.verticalCenterOffset: parent.height * 0.12

		MouseArea {
			anchors.fill: parent
			onClicked: {}
		}

		Row {
			anchors.fill: parent
			anchors.margins: 24
			spacing: 20

			// ---------- left: month grid ----------
			Column {
				id: leftCol
				width: 468
				height: parent.height
				spacing: 14

				// header
				Item {
					width: parent.width
					height: monthTitle.implicitHeight + yearLabel.implicitHeight

					Text {
						id: monthTitle
						anchors.left: parent.left
						anchors.top: parent.top
						text: root.monthNames[root.viewMonth]
						color: Theme.strong
						font.pixelSize: 26
					}

					Text {
						id: yearLabel
						anchors.left: parent.left
						anchors.top: monthTitle.bottom
						text: "" + root.viewYear
						color: Theme.muted
						font.pixelSize: 13
					}

					Row {
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						spacing: 10

						Rectangle {
							width: 30
							height: 30
							radius: 8
							color: prevHover.containsMouse ? Theme.surface : Theme.chrome
							Text {
								anchors.centerIn: parent
								text: "‹"
								color: Theme.text
								font.pixelSize: 18
							}
							MouseArea {
								id: prevHover
								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: root.prevMonth()
							}
						}

						Rectangle {
							width: 30
							height: 30
							radius: 8
							color: todayHover.containsMouse ? Theme.surface : Theme.chrome
							Text {
								anchors.centerIn: parent
								text: "•"
								color: Theme.accent
								font.pixelSize: 16
							}
							MouseArea {
								id: todayHover
								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								// Jump back to the current month + select today.
								onClicked: root.seedToday()
							}
						}

						Rectangle {
							width: 30
							height: 30
							radius: 8
							color: nextHover.containsMouse ? Theme.surface : Theme.chrome
							Text {
								anchors.centerIn: parent
								text: "›"
								color: Theme.text
								font.pixelSize: 18
							}
							MouseArea {
								id: nextHover
								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: root.nextMonth()
							}
						}
					}
				}

				// weekday header
				Row {
					width: parent.width
					Repeater {
						model: root.weekdayLetters
						delegate: Item {
							required property var modelData
							width: leftCol.width / 7
							height: 20
							Text {
								anchors.centerIn: parent
								text: parent.modelData
								color: Theme.muted
								font.pixelSize: 12
							}
						}
					}
				}

				// day grid
				Grid {
					id: grid
					width: parent.width
					columns: 7
					rowSpacing: 2
					columnSpacing: 0

					Repeater {
						model: root.cells

						delegate: Item {
							id: cell
							required property var modelData
							readonly property bool isToday: modelData.key === root.todayKey
							readonly property bool isSelected: modelData.key === root.selectedKey
							readonly property bool hasEvents: (root.eventsByDay[modelData.key] || []).length > 0
							width: leftCol.width / 7
							height: 52

							Rectangle {
								anchors.centerIn: parent
								width: 38
								height: 38
								radius: 10
								color: cell.isToday ? Theme.sage : (cell.isSelected ? Theme.surface : (cellHover.containsMouse ? Theme.chrome : "transparent"))
								border.width: (cell.isSelected && !cell.isToday) ? 1 : 0
								border.color: Theme.accent

								Text {
									anchors.centerIn: parent
									text: "" + cell.modelData.day
									color: cell.isToday ? Theme.depth : (cell.modelData.inMonth ? Theme.text : Theme.muted)
									opacity: cell.modelData.inMonth ? 1 : 0.45
									font.pixelSize: 14
									font.bold: cell.isToday
								}

								// event dot
								Rectangle {
									visible: cell.hasEvents
									width: 4
									height: 4
									radius: 2
									color: cell.isToday ? Theme.depth : Theme.accent
									anchors.horizontalCenter: parent.horizontalCenter
									anchors.bottom: parent.bottom
									anchors.bottomMargin: 4
								}
							}

							MouseArea {
								id: cellHover
								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: root.selectedKey = cell.modelData.key
							}
						}
					}
				}
			}

			// divider
			Rectangle {
				width: 1
				height: parent.height
				color: Theme.border
			}

			// ---------- right: selected day + events ----------
			Column {
				id: rightCol
				width: parent.width - leftCol.width - 20 - 1 - 40
				height: parent.height
				spacing: 12

				Text {
					text: Qt.formatDate(root.selectedDate(), "ddd").toUpperCase()
					color: Theme.muted
					font.pixelSize: 13
				}

				Text {
					text: "" + root.selectedDate().getDate()
					color: Theme.strong
					font.pixelSize: 40
					font.bold: true
				}

				Rectangle {
					width: parent.width
					height: 1
					color: Theme.border
				}

				// empty state
				Text {
					visible: root.selectedEvents.length === 0
					width: parent.width
					text: root.eventsOk ? "No events" : "No calendar connected"
					color: Theme.muted
					font.pixelSize: 13
					wrapMode: Text.WordWrap
				}

				ListView {
					id: eventList
					visible: root.selectedEvents.length > 0
					width: parent.width
					height: parent.height - y
					clip: true
					spacing: 8
					model: root.selectedEvents
					boundsBehavior: Flickable.StopAtBounds

					delegate: Rectangle {
						id: evDelegate
						required property var modelData
						width: eventList.width
						height: evCol.implicitHeight + 20
						radius: 10
						color: Theme.chrome

						Column {
							id: evCol
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							anchors.leftMargin: 14
							anchors.rightMargin: 14
							spacing: 3

							Text {
								width: parent.width
								text: evDelegate.modelData.title
								color: Theme.strong
								font.pixelSize: 14
								elide: Text.ElideRight
							}

							Text {
								width: parent.width
								text: root.fmtRange(evDelegate.modelData)
								color: Theme.muted
								font.pixelSize: 12
							}
						}
					}
				}
			}
		}
	}

	// Whether a real calendar is connected (the sync file reported ok). Purely
	// for the empty-state wording; shell.qml sets it from the JSON.
	property bool eventsOk: false
}

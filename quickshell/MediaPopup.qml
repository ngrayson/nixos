import QtQuick
import Quickshell
import Quickshell.Io

// Media control popup, opened by RIGHT-clicking the now-playing bar widget
// (Nick's choice, 2026-09-04: left-click stays play/pause on the bar, right
// opens this). Rendered as a small dropdown anchored just below the media pill
// (a grabFocus PopupWindow in shell.qml, reusing the same xdg-popup anchoring
// the bar's hover tooltip uses), not a full-screen overlay. Esc dismisses;
// clicking outside dismisses via the popup's grabbed focus. This content sizes
// itself (contentWidth/contentHeight) so the hosting PopupWindow fits it.
//
// The player object (`Quickshell.Services.Mpris` MprisPlayer) is passed down
// from shell.qml rather than resolved here, so the bar and the popup always
// act on the same player. Everything is guarded with optional chaining: the
// player can be null or swap tracks while the popup is open.
Item {
	id: root

	property bool active: false
	// shellRoot.mediaPlayer -- the same MPRIS player the bar widget drives.
	property var player: null

	signal dismissed()

	// Natural size of the dropdown, exported so the hosting PopupWindow can size
	// to it. Replaces the old full-screen overlay wrapper.
	readonly property int contentWidth: 440
	readonly property int contentHeight: cardCol.implicitHeight + 40
	implicitWidth: root.contentWidth
	implicitHeight: root.contentHeight

	readonly property bool playing: root.player?.isPlaying ?? false
	readonly property real lenSec: root.player?.length ?? 0
	// Polled from player.position each tick rather than bound directly:
	// MprisPlayer.position does not emit a change on its own, and its notify
	// signal is not callable from QML, so a plain binding would sit frozen.
	property real posSec: 0

	// Real per-frequency-band levels for the visualizer: `vizRow.barCount`
	// integers 0..100, updated once per cava frame from qs-cava-viz's stdout.
	// Empty when nothing is playing, which flattens the bars.
	property var vizLevels: []

	// Real audio-reactive data: qs-cava-viz streams cava's raw ascii output, one
	// line per frame (`barCount` semicolon-separated 0..100 values plus a
	// trailing empty field). Runs ONLY while the popup is open AND a track is
	// playing, so nothing captures audio in the background; when it stops, the
	// levels are cleared so the bars flatten instead of freezing on the last
	// frame.
	Process {
		id: cavaProc
		command: ["qs-cava-viz"]
		running: root.active && root.playing
		stdout: SplitParser {
			splitMarker: "\n"
			onRead: line => {
				const parts = line.split(";");
				const out = [];
				for (let i = 0; i < parts.length; ++i) {
					if (parts[i] === "")
						continue;
					const n = parseInt(parts[i], 10);
					out.push(isNaN(n) ? 0 : n);
				}
				root.vizLevels = out;
			}
		}
		onRunningChanged: {
			if (!running)
				root.vizLevels = [];
		}
	}

	function fmtTime(sec: real): string {
		if (!sec || sec < 0)
			return "0:00";
		const whole = Math.floor(sec);
		const s = whole % 60;
		const m = Math.floor(whole / 60);
		return m + ":" + (s < 10 ? "0" + s : s);
	}

	Shortcut {
		enabled: root.active
		sequence: "Esc"
		onActivated: root.dismissed()
	}

	// Re-reads the play position so the scrubber tracks smoothly. Only runs
	// while the popup is open. (The visualizer is driven by cava, not this.)
	Timer {
		interval: 90
		running: root.active
		repeat: true
		onTriggered: root.posSec = root.player?.position ?? 0
	}

	// Seed the position immediately on open so the scrubber isn't at 0 for the
	// first tick.
	onActiveChanged: {
		if (root.active)
			root.posSec = root.player?.position ?? 0;
	}

	// The card IS the dropdown now: it fills the popup surface (which is sized to
	// root.contentWidth/Height), rather than floating centred inside a
	// full-screen scrim. No dimming and no click-catcher -- outside-click
	// dismissal comes from the hosting PopupWindow's grabbed focus.
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
			spacing: 16

			// --- header: art + title/artist/app ---
			Row {
				width: parent.width
				spacing: 12

				Rectangle {
					width: 56
					height: 56
					radius: 6
					color: Theme.chrome
					clip: true

					Image {
						anchors.fill: parent
						source: root.player?.trackArtUrl ?? ""
						fillMode: Image.PreserveAspectCrop
						asynchronous: true
						visible: status === Image.Ready
					}

					Text {
						anchors.centerIn: parent
						visible: !(root.player?.trackArtUrl ?? "")
						text: String.fromCodePoint(0xF075A) // nf-md-music
						color: Theme.muted
						font.pixelSize: 24
						font.family: "IosevkaTermSlab NF"
					}
				}

				Column {
					width: parent.width - 56 - 12
					anchors.verticalCenter: parent.verticalCenter
					spacing: 3

					Text {
						width: parent.width
						text: (root.player?.trackTitle || "").trim() || (root.player?.identity ?? "Media")
						color: Theme.strong
						font.pixelSize: 15
						elide: Text.ElideRight
					}

					Text {
						width: parent.width
						text: (root.player?.trackArtist || "").trim()
						color: Theme.text
						font.pixelSize: 13
						elide: Text.ElideRight
						visible: text.length > 0
					}

					Text {
						width: parent.width
						text: root.player?.identity ?? ""
						color: Theme.muted
						font.pixelSize: 11
						elide: Text.ElideRight
						visible: text.length > 0
					}
				}
			}

			// --- visualizer ---
			Row {
				id: vizRow
				width: parent.width
				height: 42
				spacing: 3

				readonly property int barCount: 26
				readonly property real barW: (width - (barCount - 1) * spacing) / barCount

				Repeater {
					model: vizRow.barCount

					delegate: Rectangle {
						required property int index
						width: vizRow.barW
						radius: 2
						anchors.bottom: parent.bottom
						color: root.playing ? Theme.sage : Theme.chrome

						// Real cava level for this band (0..100), scaled to the
						// row's height. Flattens to the 4px floor when nothing is
						// playing (vizLevels is empty then, so the lookup is 0).
						height: {
							if (!root.playing)
								return 4;
							const headroom = vizRow.height - 8;
							const raw = root.vizLevels[index] ?? 0;
							const level = Math.max(0, Math.min(100, raw));
							return 4 + headroom * (level / 100);
						}

						Behavior on height {
							NumberAnimation {
								duration: 90
								easing.type: Easing.OutQuad
							}
						}
					}
				}
			}

			// --- progress scrubber ---
			Column {
				width: parent.width
				spacing: 5

				Rectangle {
					id: track
					width: parent.width
					height: 6
					radius: 3
					color: Theme.chrome

					Rectangle {
						height: parent.height
						radius: 3
						color: Theme.accent
						width: parent.width * (root.lenSec > 0 ? Math.min(1, root.posSec / root.lenSec) : 0)
					}

					MouseArea {
						anchors.fill: parent
						enabled: (root.player?.canSeek ?? false) && root.lenSec > 0
						cursorShape: Qt.PointingHandCursor
						// MprisPlayer.seek is RELATIVE, so seek by the delta from
						// where we are to the clicked fraction of the track.
						onClicked: mouse => {
							const frac = Math.max(0, Math.min(1, mouse.x / width));
							root.player.seek(frac * root.lenSec - root.posSec);
						}
					}
				}

				Item {
					width: parent.width
					height: elapsed.implicitHeight

					Text {
						id: elapsed
						anchors.left: parent.left
						text: root.fmtTime(root.posSec)
						color: Theme.muted
						font.pixelSize: 11
					}

					Text {
						anchors.right: parent.right
						text: root.fmtTime(root.lenSec)
						color: Theme.muted
						font.pixelSize: 11
					}
				}
			}

			// --- transport controls ---
			Row {
				anchors.horizontalCenter: parent.horizontalCenter
				spacing: 22

				// Previous
				Rectangle {
					width: 44
					height: 36
					radius: 8
					readonly property bool avail: root.player?.canGoPrevious ?? false
					color: prevHover.containsMouse && avail ? Theme.surface : Theme.chrome
					border.width: 1
					border.color: Theme.border
					opacity: avail ? 1 : 0.4

					Text {
						anchors.centerIn: parent
						text: String.fromCodePoint(0xF04AE) // nf-md-skip_previous
						color: Theme.text
						font.pixelSize: 16
						font.family: "IosevkaTermSlab NF"
					}

					MouseArea {
						id: prevHover
						anchors.fill: parent
						hoverEnabled: true
						enabled: parent.avail
						cursorShape: Qt.PointingHandCursor
						onClicked: root.player.previous()
					}
				}

				// Play / pause
				Rectangle {
					width: 52
					height: 36
					radius: 8
					readonly property bool avail: root.player?.canTogglePlaying ?? false
					color: playHover.containsMouse && avail ? Theme.surface : Theme.selection
					border.width: 1
					border.color: Theme.accent
					opacity: avail ? 1 : 0.4

					Text {
						anchors.centerIn: parent
						text: root.playing ? String.fromCodePoint(0xF03E4) // nf-md-pause
							: String.fromCodePoint(0xF040A) // nf-md-play
						color: Theme.bright
						font.pixelSize: 18
						font.family: "IosevkaTermSlab NF"
					}

					MouseArea {
						id: playHover
						anchors.fill: parent
						hoverEnabled: true
						enabled: parent.avail
						cursorShape: Qt.PointingHandCursor
						onClicked: root.player.togglePlaying()
					}
				}

				// Next
				Rectangle {
					width: 44
					height: 36
					radius: 8
					readonly property bool avail: root.player?.canGoNext ?? false
					color: nextHover.containsMouse && avail ? Theme.surface : Theme.chrome
					border.width: 1
					border.color: Theme.border
					opacity: avail ? 1 : 0.4

					Text {
						anchors.centerIn: parent
						text: String.fromCodePoint(0xF04AD) // nf-md-skip_next
						color: Theme.text
						font.pixelSize: 16
						font.family: "IosevkaTermSlab NF"
					}

					MouseArea {
						id: nextHover
						anchors.fill: parent
						hoverEnabled: true
						enabled: parent.avail
						cursorShape: Qt.PointingHandCursor
						onClicked: root.player.next()
					}
				}
			}
		}
	}
}

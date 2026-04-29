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
	property int audioPercent: 0
	property bool audioMuted: false
	property bool audioOsdVisible: false

	function audioIcon(): string {
		if (audioMuted)
			return "󰖁";
		if (audioPercent < 34)
			return "󰕿";
		if (audioPercent < 67)
			return "󰖀";
		return "󰕾";
	}

	function refreshAudio(): void {
		readAudio.command = ["sh", "-lc", "printf \"%s %s\" \"$(pamixer --get-volume)\" \"$(pamixer --get-mute)\""];
		readAudio.running = true;
	}

	function runAudioAction(cmd: string, showOsd: bool): void {
		audioAction.showOsdAfterExit = showOsd;
		audioAction.command = ["sh", "-lc", cmd];
		audioAction.running = true;
	}

	function showAudioOsd(): void {
		audioOsdVisible = true;
		osdHideTimer.restart();
	}

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

	IpcHandler {
		target: "audio"

		function notifyChange(): void {
			refreshAudio();
			showAudioOsd();
		}
	}

	Process {
		id: readAudio
		running: false

		onExited: exitCode => {
			if (exitCode !== 0 || !stdout)
				return;
			const out = stdout.toString().trim().split(/\s+/);
			const vol = parseInt(out[0] ?? "0");
			const muted = (out[1] ?? "false") === "true";
			if (!Number.isNaN(vol))
				shellRoot.audioPercent = Math.max(0, Math.min(150, vol));
			shellRoot.audioMuted = muted;
		}
	}

	Process {
		id: audioAction
		running: false
		property bool showOsdAfterExit: false

		onExited: _ => {
			shellRoot.refreshAudio();
			if (showOsdAfterExit)
				shellRoot.showAudioOsd();
			showOsdAfterExit = false;
		}
	}

	Timer {
		id: osdHideTimer
		interval: 1200
		repeat: false
		onTriggered: shellRoot.audioOsdVisible = false
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

				Rectangle {
					radius: 8
					color: "#313244"
					implicitHeight: 24
					implicitWidth: 30

					Text {
						id: audioLabel
						anchors.centerIn: parent
						color: "#cdd6f4"
						font.pixelSize: 14
						font.family: "IosevkaTermSlab NF"
						text: shellRoot.audioIcon()
					}

					MouseArea {
						anchors.fill: parent
						hoverEnabled: true
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						scrollGestureEnabled: false
						onClicked: mouse => {
							if (mouse.button === Qt.LeftButton)
								shellRoot.runAudioAction("pavucontrol", false);
							else if (mouse.button === Qt.RightButton)
								shellRoot.runAudioAction("pamixer -t", true);
						}
						onWheel: event => {
							if (event.angleDelta.y > 0)
								shellRoot.runAudioAction("pamixer -i 5", true);
							else if (event.angleDelta.y < 0)
								shellRoot.runAudioAction("pamixer -d 5", true);
						}
					}
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

				Timer {
					running: true
					repeat: true
					interval: 2000
					onTriggered: shellRoot.refreshAudio()
				}

				Component.onCompleted: shellRoot.refreshAudio()
			}
		}
	}

	Variants {
		model: Quickshell.screens

		PanelWindow {
			required property var modelData
			readonly property bool isCenterScreen: {
				const c = shellRoot.centerOutputScreen();
				return c && modelData && c.name === modelData.name;
			}

			screen: modelData
			color: "transparent"
			visible: isCenterScreen && shellRoot.audioOsdVisible

			anchors.top: true
			anchors.bottom: true
			anchors.left: true
			anchors.right: true

			Rectangle {
				width: 250
				height: 88
				radius: 12
				color: "#1e1e2e"
				border.width: 1
				border.color: "#45475a"
				anchors.centerIn: parent

				ColumnLayout {
					anchors.fill: parent
					anchors.margins: 12
					spacing: 8

					Text {
						Layout.alignment: Qt.AlignHCenter
						text: shellRoot.audioIcon()
						color: "#cdd6f4"
						font.pixelSize: 20
						font.family: "IosevkaTermSlab NF"
					}

					Rectangle {
						id: osdMeter
						Layout.fillWidth: true
						Layout.preferredHeight: 8
						radius: 4
						color: "#313244"

						Rectangle {
							anchors.left: parent.left
							anchors.verticalCenter: parent.verticalCenter
							width: shellRoot.audioPercent > 0 ? Math.max(6, Math.min(parent.width, parent.width * (shellRoot.audioPercent / 100.0))) : 0
							height: parent.height
							radius: parent.radius
							color: shellRoot.audioMuted ? "#6c7086" : "#89b4fa"
						}
					}
				}
			}
		}
	}
}

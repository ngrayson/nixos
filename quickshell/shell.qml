// Quickshell: top bar (Hyprland workspaces + clock) + WlSessionLock (PAM password).
// One bar per output via `Variants` + `Quickshell.screens` (not follow-focus on a single PanelWindow).
// Lock: `quickshell ipc -p ~/.config/quickshell -n call lock activate` (see `quickshell-lock`).
// Debug: `quickshell ipc -p ~/.config/quickshell show` (subcommand is `ipc`, not a bare `show` flag).
// Audio debug overlay: `quickshell ipc -p ~/.config/quickshell call audio toggleDebug`
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Networking
import Quickshell.Bluetooth

ShellRoot {
	id: shellRoot
	property int audioPercent: 0
	property bool audioMuted: false
	property bool audioOsdVisible: false
	property bool debugAudio: false
	property string audioDebugRaw: ""
	property int audioLastExitCode: -999
	readonly property int topBarHeight: 32

	// Desktops still expose a DisplayDevice, it just is not a laptop battery, so the pill hides
	// itself at runtime and this file stays host-agnostic (unlike the fastfetch battery fragment).
	readonly property var battery: UPower.displayDevice
	readonly property bool batteryPresent: battery?.isLaptopBattery ?? false
	// UPowerDevice.percentage is energy/energyCapacity, i.e. 0.0-1.0, not 0-100.
	readonly property int batteryPercent: Math.round((battery?.percentage ?? 0) * 100)
	readonly property bool batteryCharging: battery?.state === UPowerDeviceState.Charging
	readonly property bool batteryLow: batteryPresent && !batteryCharging && batteryPercent <= 15
	readonly property int powerProfile: PowerProfiles.profile
	readonly property bool powerProfileMarked: powerProfile !== PowerProfile.Balanced

	readonly property var netWifiDevice: {
		const devices = Networking.devices.values;
		for (let i = 0; i < devices.length; ++i) {
			const d = devices[i];
			if (d.type === DeviceType.Wifi && d.connected)
				return d;
		}
		return null;
	}
	readonly property var netWifiNetwork: {
		const d = netWifiDevice;
		if (!d)
			return null;
		const nets = d.networks.values;
		for (let i = 0; i < nets.length; ++i) {
			if (nets[i].connected)
				return nets[i];
		}
		return null;
	}
	readonly property var netWiredDevice: {
		const devices = Networking.devices.values;
		for (let i = 0; i < devices.length; ++i) {
			const d = devices[i];
			if (d.type === DeviceType.Wired && d.connected)
				return d;
		}
		return null;
	}
	readonly property bool networkRadioOff: !Networking.wifiEnabled || !Networking.wifiHardwareEnabled
	// Prefer wifi, else wired, else off / disconnected.
	readonly property string networkKind: {
		if (netWifiDevice)
			return "wifi";
		if (netWiredDevice)
			return "wired";
		if (networkRadioOff)
			return "off";
		return "disconnected";
	}
	readonly property int networkSignal: Math.round(netWifiNetwork?.signalStrength ?? 0)
	readonly property bool networkBusy: {
		const d = netWifiDevice ?? netWiredDevice;
		if (!d)
			return false;
		return d.state === ConnectionState.Connecting || d.state === ConnectionState.Disconnecting;
	}

	readonly property var btAdapter: Bluetooth.defaultAdapter
	readonly property bool btPresent: btAdapter !== null
	readonly property bool btEnabled: btAdapter?.enabled ?? false
	readonly property bool btBusy: {
		const s = btAdapter?.state;
		return s === BluetoothAdapterState.Enabling || s === BluetoothAdapterState.Disabling;
	}
	readonly property bool btBlocked: btAdapter?.state === BluetoothAdapterState.Blocked
	readonly property int btConnectedCount: {
		const devices = Bluetooth.devices.values;
		let n = 0;
		for (let i = 0; i < devices.length; ++i) {
			if (devices[i].connected)
				n++;
		}
		return n;
	}

	function audioIcon(): string {
		if (audioMuted)
			return "󰖁";
		if (audioPercent < 34)
			return "󰕿";
		if (audioPercent < 67)
			return "󰖀";
		return "󰕾";
	}

	function batteryIcon(): string {
		// Codepoints (not literal PUA glyphs): editing tools mangle nf-md private-use chars.
		if (batteryCharging)
			return String.fromCodePoint(0xF0084); // nf-md-battery_charging
		if (batteryPercent >= 95)
			return String.fromCodePoint(0xF0079); // nf-md-battery (full)
		if (batteryPercent < 10)
			return String.fromCodePoint(0xF008E); // nf-md-battery_outline (empty)
		// nf-md-battery_10 .. battery_90 are contiguous from F007A.
		return String.fromCodePoint(0xF007A + Math.min(8, Math.floor(batteryPercent / 10) - 1));
	}

	function powerProfileIcon(): string {
		if (powerProfile === PowerProfile.PowerSaver)
			return String.fromCodePoint(0xF06A5); // nf-md-leaf
		if (powerProfile === PowerProfile.Performance)
			return String.fromCodePoint(0xF0A0D); // nf-md-speedometer
		return "";
	}

	function powerProfileLabel(): string {
		if (powerProfile === PowerProfile.PowerSaver)
			return "Power Saver";
		if (powerProfile === PowerProfile.Performance)
			return "Performance";
		return "Balanced";
	}

	function cyclePowerProfile(): void {
		const cur = PowerProfiles.profile;
		let next = PowerProfile.PowerSaver;
		if (cur === PowerProfile.PowerSaver)
			next = PowerProfile.Balanced;
		else if (cur === PowerProfile.Balanced)
			next = PowerProfiles.hasPerformanceProfile ? PowerProfile.Performance : PowerProfile.PowerSaver;
		// Performance (or unknown) -> PowerSaver
		PowerProfiles.profile = next;
		notifyPowerProfile();
	}

	function notifyPowerProfile(): void {
		// Stack-tag replaces prior profile toasts so rapid cycling does not pile up.
		profileNotify.command = [
			"notify-send", "-e", "-a", "Power Profile",
			"-h", "string:x-dunst-stack-tag:qs-power-profile",
			"Power Profile", powerProfileLabel()
		];
		profileNotify.running = true;
	}

	function networkIcon(): string {
		if (networkKind === "wired")
			return String.fromCodePoint(0xF0200); // nf-md-ethernet
		if (networkKind === "off")
			return String.fromCodePoint(0xF05AA); // nf-md-wifi_off
		if (networkKind === "wifi") {
			const s = networkSignal;
			// nf-md-wifi_strength_{1..4}: F091F / F0922 / F0925 / F0928 (F05A6..A8 are unrelated glyphs).
			if (s >= 75)
				return String.fromCodePoint(0xF0928);
			if (s >= 50)
				return String.fromCodePoint(0xF0925);
			if (s >= 25)
				return String.fromCodePoint(0xF0922);
			if (s >= 1)
				return String.fromCodePoint(0xF091F);
		}
		return String.fromCodePoint(0xF05A9); // nf-md-wifi (disconnected / fallback)
	}

	function networkColor(): string {
		if (networkBusy)
			return "#fab387";
		if (networkKind === "disconnected" || networkKind === "off")
			return "#6c7086";
		return "#cdd6f4";
	}

	function bluetoothIcon(): string {
		if (!btEnabled || btBlocked)
			return String.fromCodePoint(0xF00B2); // nf-md-bluetooth_off
		if (btConnectedCount > 0)
			return String.fromCodePoint(0xF00B1); // nf-md-bluetooth_connect
		return String.fromCodePoint(0xF00AF); // nf-md-bluetooth
	}

	function bluetoothColor(): string {
		if (btBusy)
			return "#fab387";
		if (!btEnabled || btBlocked)
			return "#6c7086";
		if (btConnectedCount > 0)
			return "#89b4fa";
		return "#cdd6f4";
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

		function toggleDebug(): void {
			shellRoot.debugAudio = !shellRoot.debugAudio;
		}

		function debugOn(): void {
			shellRoot.debugAudio = true;
		}

		function debugOff(): void {
			shellRoot.debugAudio = false;
		}
	}

	Process {
		id: readAudio
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const raw = this.text.trim();
				shellRoot.audioDebugRaw = raw;
				if (shellRoot.debugAudio)
					console.log("[audio] stdout:", JSON.stringify(raw));
				if (!raw)
					return;
				const parts = raw.split(/\s+/).filter(Boolean);
				const vol = parseInt(parts[0] ?? "0", 10);
				const muteStr = (parts.length > 1 ? parts[parts.length - 1] : "false").toLowerCase();
				const muted = muteStr === "true" || muteStr === "1";
				if (!Number.isNaN(vol))
					shellRoot.audioPercent = Math.max(0, Math.min(150, vol));
				shellRoot.audioMuted = muted;
			}
		}

		onExited: (exitCode, _exitStatus) => {
			shellRoot.audioLastExitCode = exitCode;
			if (shellRoot.debugAudio)
				console.log("[audio] process exit code:", exitCode);
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

	Process {
		id: profileNotify
		running: false
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
			implicitHeight: shellRoot.topBarHeight
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
						implicitHeight: shellRoot.topBarHeight

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
					visible: shellRoot.debugAudio
					Layout.alignment: Qt.AlignVCenter
					color: "#fab387"
					font.pixelSize: 9
					text: shellRoot.audioPercent + "% m=" + shellRoot.audioMuted + " ex=" + shellRoot.audioLastExitCode
				}

				Rectangle {
					radius: 8
					color: "#313244"
					implicitHeight: 24
					implicitWidth: 30

					Text {
						anchors.centerIn: parent
						color: shellRoot.networkColor()
						font.pixelSize: 14
						font.family: "IosevkaTermSlab NF"
						text: shellRoot.networkIcon()
					}

					MouseArea {
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						onClicked: mouse => {
							if (mouse.button === Qt.LeftButton)
								Hyprland.dispatch("exec nmgui");
							else if (mouse.button === Qt.RightButton)
								Hyprland.dispatch("exec kitty --title nmtui nmtui");
						}
					}
				}

				Rectangle {
					visible: shellRoot.btPresent
					radius: 8
					color: "#313244"
					implicitHeight: 24
					implicitWidth: 30

					Text {
						anchors.centerIn: parent
						color: shellRoot.bluetoothColor()
						font.pixelSize: 14
						font.family: "IosevkaTermSlab NF"
						text: shellRoot.bluetoothIcon()
					}

					MouseArea {
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						onClicked: mouse => {
							if (mouse.button === Qt.LeftButton)
								Hyprland.dispatch("exec blueman-manager");
							else if (mouse.button === Qt.RightButton && shellRoot.btAdapter)
								shellRoot.btAdapter.enabled = !shellRoot.btAdapter.enabled;
						}
					}
				}

				Rectangle {
					visible: shellRoot.batteryPresent
					radius: 8
					color: "#313244"
					implicitHeight: 24
					implicitWidth: batteryRow.implicitWidth + 16

					RowLayout {
						id: batteryRow
						anchors.centerIn: parent
						spacing: 4

						Text {
							color: shellRoot.batteryLow ? "#f38ba8" : (shellRoot.batteryCharging ? "#a6e3a1" : "#cdd6f4")
							font.pixelSize: 14
							font.family: "IosevkaTermSlab NF"
							text: shellRoot.batteryIcon()
						}

						Text {
							color: shellRoot.batteryLow ? "#f38ba8" : "#cdd6f4"
							font.pixelSize: 12
							text: shellRoot.batteryPercent + "%"
						}

						Text {
							visible: shellRoot.powerProfileMarked
							color: shellRoot.powerProfile === PowerProfile.PowerSaver ? "#a6e3a1" : "#fab387"
							font.pixelSize: 14
							font.family: "IosevkaTermSlab NF"
							text: shellRoot.powerProfileIcon()
						}
					}

					MouseArea {
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton
						onClicked: shellRoot.cyclePowerProfile()
					}
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
						// Must stay true: when false, onWheel only fires for physical
						// mouse wheels, so touchpad two-finger scroll (Theseus) is dropped.
						scrollGestureEnabled: true
						onClicked: mouse => {
							if (mouse.button === Qt.LeftButton)
								shellRoot.runAudioAction("pavu-toggle", false);
							else if (mouse.button === Qt.RightButton)
								shellRoot.runAudioAction("pamixer -t", true);
						}
						onWheel: event => {
							// 1% per event: touchpad scroll fires many ticks; 5% felt too coarse.
							// Keyboard XF86 bindings stay at 5% (home/wayland/hyprland.nix).
							if (event.angleDelta.y > 0)
								shellRoot.runAudioAction("pamixer -i 1", true);
							else if (event.angleDelta.y < 0)
								shellRoot.runAudioAction("pamixer -d 1", true);
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
				height: shellRoot.debugAudio ? 118 : 88
				radius: 12
				color: "#1e1e2e"
				border.width: 1
				border.color: "#45475a"
				anchors.horizontalCenter: parent.horizontalCenter
				anchors.verticalCenter: parent.verticalCenter
				anchors.verticalCenterOffset: parent.height * 0.25

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
							color: shellRoot.debugAudio ? "#a6e3a1" : (shellRoot.audioMuted ? "#6c7086" : "#89b4fa")
						}
					}

					Text {
						visible: shellRoot.debugAudio
						Layout.fillWidth: true
						Layout.alignment: Qt.AlignHCenter
						color: "#fab387"
						font.pixelSize: 9
						wrapMode: Text.WrapAnywhere
						horizontalAlignment: Text.AlignHCenter
						text: "raw=|" + shellRoot.audioDebugRaw + "|"
					}
				}
			}
		}
	}
}

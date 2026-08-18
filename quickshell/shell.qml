//@ pragma UseQApplication
// Required for system tray context menus (QsMenuAnchor.open needs QApplication mode).
// Quickshell: top bar (Hyprland workspaces + clock) + WlSessionLock (PAM password).
// One bar per output via `Variants` + `Quickshell.screens` (not follow-focus on a single PanelWindow).
// Lock: `quickshell ipc -p ~/.config/quickshell -n call lock activate` (see `quickshell-lock`).
// Preview (not a session lock, Esc dismisses): `ipc call lock preview` (see `quickshell-lock-preview`).
// Debug: `quickshell ipc -p ~/.config/quickshell show` (subcommand is `ipc`, not a bare `show` flag).
// Audio debug overlay: `quickshell ipc -p ~/.config/quickshell call audio toggleDebug`
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

ShellRoot {
	id: shellRoot
	property int audioPercent: 0
	property bool audioMuted: false
	property bool osdVisible: false
	property string osdKind: "audio"
	property bool debugAudio: false
	property string audioDebugRaw: ""
	property int audioLastExitCode: -999
	property bool brightnessPresent: false
	property int brightnessPercent: 0
	// Framework EC keyboard backlight (chromeos::kbd_backlight). Left-click on the
	// brightness pill cycles off → 33% → 100%; the OSD shows the new level.
	property bool kbdBrightnessPresent: false
	property int kbdBrightnessPercent: 0
	property bool brightnessOsdPending: false
	// Set before a user-initiated kbd read so the startup/silent read does not flash the OSD.
	property bool kbdFeedbackPending: false
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
	readonly property int networkSignal: Math.round((netWifiNetwork?.signalStrength ?? 0) * 100)
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

	// Prefer a currently-playing MPRIS player; otherwise the first registered one.
	readonly property var mediaPlayer: {
		const players = Mpris.players.values;
		for (let i = 0; i < players.length; ++i) {
			if (players[i].isPlaying)
				return players[i];
		}
		return players.length > 0 ? players[0] : null;
	}
	readonly property bool mediaPresent: mediaPlayer !== null

	readonly property var micSource: Pipewire.defaultAudioSource
	readonly property bool micPresent: micSource !== null && micSource.ready && micSource.audio !== null
	readonly property bool micMuted: micPresent && micSource.audio.muted
	readonly property bool micActive: micPresent && micLinkTracker.linkGroups.length > 0

	PwObjectTracker {
		// PwNode.audio properties are invalid until their parent node is bound.
		objects: shellRoot.micSource ? [shellRoot.micSource] : []
	}

	PwNodeLinkTracker {
		id: micLinkTracker
		// Tracks capture streams attached to the default input, excluding monitors.
		node: shellRoot.micSource
	}

	function micIcon(): string {
		return String.fromCodePoint(micMuted ? 0xF036D : 0xF036C); // nf-md-microphone_{off,on}
	}

	function micColor(): string {
		if (micMuted)
			return "#6c7086";
		if (micActive)
			return "#f38ba8";
		return "#cdd6f4";
	}

	// Wayland idle-inhibit: when true, hypridle (ignore_dbus_inhibit=false) will not
	// lock/suspend. Bound to each bar PanelWindow below.
	property bool idleInhibited: false

	// Fullscreen overlay that looks like the lock but is not WlSessionLock. Esc dismisses.
	property bool lockPreview: false

	// Tray icons hidden behind a chevron; the pill keeps the chevron + item count.
	property bool trayCollapsed: false

	// Hidden while the running system matches the flake and flake.lock is current.
	property bool nixosRebuildPending: false
	property int nixosUpdates: 0
	property bool qsReloadPending: false
	property bool qsReloadWatchArmed: false

	function markQsReloadPending(): void {
		if (qsReloadWatchArmed)
			qsReloadPending = true;
	}

	function hyprWorkspace(id: int): var {
		const list = Hyprland.workspaces.values;
		for (let i = 0; i < list.length; ++i) {
			if (list[i].id === id)
				return list[i];
		}
		return null;
	}

	function nixosStatusVisible(): bool {
		return nixosRebuildPending || nixosUpdates > 0;
	}

	function refreshNixosStatus(force: bool): void {
		if (readNixosStatus.running)
			return;
		readNixosStatus.command = force ? ["qs-nixos-status", "--force"] : ["qs-nixos-status"];
		readNixosStatus.running = true;
	}

	function nixosTooltipText(): string {
		const lines = [];
		if (nixosRebuildPending)
			lines.push("Wrench: flake config is not what this machine is running");
		if (nixosUpdates > 0)
			lines.push("Updates: " + nixosUpdates + " flake input" + (nixosUpdates === 1 ? "" : "s") + " newer than flake.lock");
		lines.push("Left-click: rebuild (os-rebuild switch)");
		lines.push("Right-click: update flake inputs");
		lines.push("Shift+click: refresh this status");
		return lines.join("\n");
	}

	function wifiTooltipText(): string {
		const lines = [];
		if (networkKind === "wifi") {
			const ssid = (netWifiNetwork?.name || "Wi-Fi").trim();
			lines.push(ssid + " · " + networkSignal + "%");
		} else if (networkKind === "wired") {
			lines.push("Ethernet" + (netWiredDevice?.name ? " · " + netWiredDevice.name : ""));
		} else if (networkKind === "off") {
			lines.push("Wi-Fi radio off");
		} else {
			lines.push("Disconnected");
		}
		lines.push("Left-click: network manager");
		lines.push("Right-click: nmtui");
		return lines.join("\n");
	}

	function bluetoothTooltipText(): string {
		const lines = [];
		if (btBlocked)
			lines.push("Bluetooth blocked");
		else if (!btEnabled)
			lines.push("Bluetooth off");
		else if (btConnectedCount > 0)
			lines.push("Bluetooth · " + btConnectedCount + " connected");
		else
			lines.push("Bluetooth on · no devices");
		lines.push("Left-click: Blueman");
		lines.push("Right-click: toggle adapter");
		return lines.join("\n");
	}

	function brightnessTooltipText(): string {
		const lines = ["Display " + brightnessPercent + "%"];
		if (kbdBrightnessPresent)
			lines.push("Keyboard " + kbdBrightnessPercent + "%");
		lines.push("Scroll: display brightness");
		if (kbdBrightnessPresent)
			lines.push("Left-click: cycle keyboard backlight");
		return lines.join("\n");
	}

	function batteryTooltipText(): string {
		let status = batteryPercent + "%";
		if (batteryCharging)
			status += " · charging";
		else if (batteryLow)
			status += " · low";
		const lines = [status, "Profile: " + powerProfileLabel()];
		lines.push("Left-click: cycle power profile");
		return lines.join("\n");
	}

	function idleTooltipText(): string {
		return (idleInhibited ? "Keep awake on · idle lock/suspend blocked" : "Keep awake off")
			+ "\nLeft-click: toggle";
	}

	function micTooltipText(): string {
		const lines = [];
		if (micMuted)
			lines.push("Microphone muted");
		else if (micActive)
			lines.push("Microphone in use");
		else
			lines.push("Microphone ready");
		lines.push("Left-click: mute/unmute");
		lines.push("Right-click: input devices");
		return lines.join("\n");
	}

	function audioTooltipText(): string {
		const lines = [audioMuted ? "Muted" : ("Volume " + audioPercent + "%")];
		lines.push("Left-click: pavucontrol");
		lines.push("Right-click: mute");
		lines.push("Scroll: 1%");
		return lines.join("\n");
	}

	function qsReloadTooltipText(): string {
		return "Quickshell source changed\nLeft-click: reload bar";
	}

	function barTooltipText(kind: string): string {
		if (kind === "nixos")
			return nixosTooltipText();
		if (kind === "qsreload")
			return qsReloadTooltipText();
		if (kind === "wifi")
			return wifiTooltipText();
		if (kind === "bt")
			return bluetoothTooltipText();
		if (kind === "brightness")
			return brightnessTooltipText();
		if (kind === "battery")
			return batteryTooltipText();
		if (kind === "idle")
			return idleTooltipText();
		if (kind === "mic")
			return micTooltipText();
		if (kind === "audio")
			return audioTooltipText();
		return "";
	}

	function idleInhibitIcon(): string {
		return String.fromCodePoint(0xEC15); // nf-cod-flame
	}

	function idleInhibitColor(): string {
		return idleInhibited ? "#f9e2af" : "#6c7086";
	}

	function mediaIcon(): string {
		// Pause glyph while playing (click will pause); play glyph otherwise.
		if (mediaPlayer?.isPlaying)
			return String.fromCodePoint(0xF03E4); // nf-md-pause
		return String.fromCodePoint(0xF040A); // nf-md-play
	}

	function mediaLabel(): string {
		const t = (mediaPlayer?.trackTitle || "").trim();
		const label = t || (mediaPlayer?.identity || "Media");
		return label.length > 28 ? label.slice(0, 27) + "…" : label;
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
			// WifiNetwork.signalStrength is 0.0-1.0 (already scaled into networkSignal 0-100).
			// nf-md-wifi_strength_{1..4}: F091F / F0922 / F0925 / F0928.
			const s = networkSignal;
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

	function brightnessIcon(): string {
		// MDI brightness_1 is a solid disk (reads as a full moon), so low levels use the
		// moon-phase set. Sun glyphs are not ordered by fill in the font, so pick them
		// explicitly: empty → half → crescent → full.
		const p = brightnessPercent;
		if (p < 15)
			return String.fromCodePoint(0xF0F64); // nf-md-moon_new
		if (p < 30)
			return String.fromCodePoint(0xF0F67); // nf-md-moon_waxing_crescent
		if (p < 45)
			return String.fromCodePoint(0xF00DB); // nf-md-brightness_2 (thick crescent)
		if (p < 60)
			return String.fromCodePoint(0xF00DE); // nf-md-brightness_5 (empty sun)
		if (p < 75)
			return String.fromCodePoint(0xF00DF); // nf-md-brightness_6 (half sun)
		if (p < 90)
			return String.fromCodePoint(0xF00DD); // nf-md-brightness_4 (crescent sun)
		return String.fromCodePoint(0xF00E0); // nf-md-brightness_7 (full sun)
	}

	// Without an explicit class, brightnessctl falls back to the first device it finds,
	// which on hosts with no panel backlight (desktops) is a keyboard LED with max=1 —
	// that reads as 0%/100% and toggles scrolllock instead of the screen.
	function refreshBrightness(): void {
		if (!readBrightness.running) {
			readBrightness.command = ["brightnessctl", "-c", "backlight", "-m"];
			readBrightness.running = true;
		}
	}

	function adjustBrightness(delta: int): void {
		if (brightnessAction.running)
			return;
		brightnessOsdPending = true;
		brightnessAction.command = ["brightnessctl", "-c", "backlight", "-q", "set", delta > 0 ? "+1%" : "1%-"];
		brightnessAction.running = true;
	}

	function kbdBrightnessIcon(): string {
		return String.fromCodePoint(0xF030C); // nf-md-keyboard
	}

	function refreshKbdBrightness(): void {
		if (!readKbdBrightness.running) {
			readKbdBrightness.command = ["brightnessctl", "-m", "-d", "chromeos::kbd_backlight"];
			readKbdBrightness.running = true;
		}
	}

	// Mirrors the Framework hardware key: off -> dim -> full.
	function cycleKbdBrightness(): void {
		if (kbdAction.running)
			return;
		const p = kbdBrightnessPercent;
		const next = p === 0 ? 33 : (p < 67 ? 100 : 0);
		kbdFeedbackPending = true;
		kbdAction.command = ["brightnessctl", "-q", "-d", "chromeos::kbd_backlight", "set", next + "%"];
		kbdAction.running = true;
	}

	function showKbdBrightnessFeedback(): void {
		showOsd("kbd");
	}

	function refreshAudio(): void {
		readAudio.command = ["sh", "-lc", "printf \"%s %s\" \"$(pamixer --get-volume)\" \"$(pamixer --get-mute)\""];
		readAudio.running = true;
	}

	function runAudioAction(cmd: string, showOsdAfter: bool): void {
		audioAction.showOsdAfterExit = showOsdAfter;
		audioAction.command = ["sh", "-lc", cmd];
		audioAction.running = true;
	}

	function showAudioOsd(): void {
		showOsd("audio");
	}

	function showOsd(kind: string): void {
		osdKind = kind;
		osdVisible = true;
		osdHideTimer.restart();
	}

	function osdIcon(): string {
		if (osdKind === "brightness")
			return brightnessIcon();
		if (osdKind === "kbd")
			return kbdBrightnessIcon();
		return audioIcon();
	}

	function osdPercent(): int {
		if (osdKind === "brightness")
			return brightnessPercent;
		if (osdKind === "kbd")
			return kbdBrightnessPercent;
		return audioPercent;
	}

	function osdFillColor(): string {
		if (osdKind === "brightness" || osdKind === "kbd")
			return "#f9e2af";
		if (debugAudio)
			return "#a6e3a1";
		if (audioMuted)
			return "#6c7086";
		return "#89b4fa";
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
			lockContext.currentText = "";
			if (shellRoot.lockPreview)
				shellRoot.lockPreview = false;
			else
				sessionLock.locked = false;
		}
	}

	WlSessionLock {
		id: sessionLock
		locked: false

		WlSessionLockSurface {
			id: lockSessionSurface
			// Wallpaper on every output (protocol still requires a surface per screen).
			// Chrome only on the center output — same idea as the SDDM greeter on Tawa.
			readonly property bool showLockUi: {
				const c = shellRoot.centerOutputScreen();
				return c && screen && c.name === screen.name;
			}

			color: "#010212"

			LockSurface {
				anchors.fill: parent
				context: lockContext
				preview: false
				showUi: lockSessionSurface.showLockUi
			}
		}
	}

	// Not a session lock: Overlay layer-shell. Esc (and a correct password) dismisses.
	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: previewWin
			required property var modelData
			readonly property bool isCenterScreen: {
				const c = shellRoot.centerOutputScreen();
				return c && modelData && c.name === modelData.name;
			}
			readonly property bool previewOpen: shellRoot.lockPreview && !sessionLock.locked

			screen: modelData
			visible: previewOpen
			color: "#010212"
			exclusionMode: ExclusionMode.Ignore
			focusable: previewOpen && isCenterScreen

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "qs-lock-preview-" + modelData.name
			WlrLayershell.keyboardFocus: (previewOpen && isCenterScreen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

			anchors.top: true
			anchors.bottom: true
			anchors.left: true
			anchors.right: true

			LockSurface {
				anchors.fill: parent
				context: lockContext
				preview: true
				showUi: previewWin.previewOpen && previewWin.isCenterScreen
				onDismissRequested: shellRoot.lockPreview = false
			}
		}
	}

	IpcHandler {
		target: "lock"

		// Return type required or quickshell will not register this for `ipc call lock activate`.
		function activate(): void {
			shellRoot.lockPreview = false;
			lockContext.currentText = "";
			sessionLock.locked = true;
		}

		function preview(): void {
			if (sessionLock.locked)
				return;
			lockContext.currentText = "";
			shellRoot.lockPreview = true;
		}

		function cancelPreview(): void {
			shellRoot.lockPreview = false;
			lockContext.currentText = "";
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

	Process {
		id: readBrightness
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const raw = this.text.trim();
				if (!raw) {
					shellRoot.brightnessPresent = false;
					return;
				}
				// brightnessctl -m: device,class,current,percent,max
				const fields = raw.split(/\r?\n/, 1)[0].split(",");
				const percent = parseInt((fields[3] ?? "").replace("%", ""), 10);
				if (!Number.isNaN(percent)) {
					shellRoot.brightnessPercent = Math.max(0, Math.min(100, percent));
					shellRoot.brightnessPresent = true;
					if (shellRoot.brightnessOsdPending) {
						shellRoot.brightnessOsdPending = false;
						shellRoot.showOsd("brightness");
					}
				}
			}
		}

		onExited: exitCode => {
			if (exitCode !== 0)
				shellRoot.brightnessPresent = false;
		}
	}

	Process {
		id: brightnessAction
		running: false
		onExited: _ => shellRoot.refreshBrightness()
	}

	Process {
		id: readKbdBrightness
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const raw = this.text.trim();
				if (!raw) {
					shellRoot.kbdBrightnessPresent = false;
					return;
				}
				const fields = raw.split(/\r?\n/, 1)[0].split(",");
				const percent = parseInt((fields[3] ?? "").replace("%", ""), 10);
				if (!Number.isNaN(percent)) {
					shellRoot.kbdBrightnessPercent = Math.max(0, Math.min(100, percent));
					shellRoot.kbdBrightnessPresent = true;
					if (shellRoot.kbdFeedbackPending) {
						shellRoot.kbdFeedbackPending = false;
						shellRoot.showKbdBrightnessFeedback();
					}
				}
			}
		}

		onExited: exitCode => {
			if (exitCode !== 0)
				shellRoot.kbdBrightnessPresent = false;
		}
	}

	Process {
		id: kbdAction
		running: false
		onExited: exitCode => {
			if (exitCode === 0)
				shellRoot.refreshKbdBrightness();
		}
	}

	readonly property string qsSourceDir: `${Quickshell.env("HOME")}/.config/nixos/quickshell`

	FileView {
		path: `${shellRoot.qsSourceDir}/shell.qml`
		watchChanges: true
		printErrors: false
		onFileChanged: shellRoot.markQsReloadPending()
	}

	FileView {
		path: `${shellRoot.qsSourceDir}/LockContext.qml`
		watchChanges: true
		printErrors: false
		onFileChanged: shellRoot.markQsReloadPending()
	}

	FileView {
		path: `${shellRoot.qsSourceDir}/LockSurface.qml`
		watchChanges: true
		printErrors: false
		onFileChanged: shellRoot.markQsReloadPending()
	}

	Timer {
		interval: 1500
		running: true
		repeat: false
		onTriggered: shellRoot.qsReloadWatchArmed = true
	}

	Process {
		id: readNixosStatus
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const raw = this.text.trim();
				if (!raw)
					return;
				try {
					const data = JSON.parse(raw);
					shellRoot.nixosRebuildPending = !!data.rebuild;
					shellRoot.nixosUpdates = Number(data.updates) || 0;
				} catch (_e) {
				}
			}
		}
	}

	FileView {
		path: `${Quickshell.env("HOME")}/.cache/qs-nixos-status/bump`
		watchChanges: true
		printErrors: false
		onFileChanged: shellRoot.refreshNixosStatus(false)
	}

	Timer {
		interval: 2000
		running: true
		repeat: true
		onTriggered: shellRoot.refreshBrightness()
	}

	Timer {
		interval: 60000
		running: true
		repeat: true
		onTriggered: shellRoot.refreshNixosStatus(false)
	}

	Timer {
		id: osdHideTimer
		interval: 1200
		repeat: false
		onTriggered: shellRoot.osdVisible = false
	}

	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: barWindow
			required property var modelData

			screen: modelData

			anchors.top: true
			anchors.left: true
			anchors.right: true
			implicitHeight: shellRoot.topBarHeight
			color: "#1e1e2e"

			property Item tipItem: null
			property string tipKind: ""
			property bool tipOn: false

			function armTip(item, kind: string): void {
				tipItem = item;
				tipKind = kind;
				tipDelay.restart();
			}

			function disarmTip(): void {
				tipDelay.stop();
				tipOn = false;
			}

			Timer {
				id: tipDelay
				interval: 400
				repeat: false
				onTriggered: barWindow.tipOn = true
			}

			// One inhibitor per output is fine; Hyprland treats a visible PanelWindow as
			// important, so this blocks hypridle while enabled.
			IdleInhibitor {
				enabled: shellRoot.idleInhibited
				window: barWindow
			}

			RowLayout {
				anchors.fill: parent
				anchors.leftMargin: 10
				anchors.rightMargin: 10
				spacing: 10

				Repeater {
					model: 10

					delegate: Rectangle {
						required property int index

						property int wid: index + 1
						property var hyprWs: shellRoot.hyprWorkspace(wid)
						property bool isFocused: Hyprland.focusedWorkspace?.id === wid
						property bool isOnMonitor: hyprWs?.active ?? false
						property bool occupied: (hyprWs?.toplevels.values.length ?? 0) > 0

						visible: isFocused || isOnMonitor || occupied
						implicitWidth: wsLabel.implicitWidth + 16
						implicitHeight: 22
						Layout.alignment: Qt.AlignVCenter
						radius: 6
						color: isFocused ? "#45475a" : (occupied ? "#313244" : "transparent")

						Text {
							id: wsLabel
							anchors.centerIn: parent
							text: parent.wid
							color: (parent.isFocused || parent.occupied) ? "#cdd6f4" : "#6c7086"
							font.pixelSize: 14
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
					visible: shellRoot.mediaPresent
					radius: 8
					color: "#313244"
					implicitHeight: 24
					implicitWidth: mediaRow.implicitWidth + 16

					RowLayout {
						id: mediaRow
						anchors.centerIn: parent
						spacing: 4

						Text {
							color: shellRoot.mediaPlayer?.isPlaying ? "#a6e3a1" : "#cdd6f4"
							font.pixelSize: 14
							font.family: "IosevkaTermSlab NF"
							text: shellRoot.mediaIcon()
						}

						Text {
							color: "#cdd6f4"
							font.pixelSize: 12
							text: shellRoot.mediaLabel()
						}
					}

					MouseArea {
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
						scrollGestureEnabled: true
						onClicked: mouse => {
							const p = shellRoot.mediaPlayer;
							if (!p)
								return;
							if (mouse.button === Qt.LeftButton && p.canTogglePlaying)
								p.togglePlaying();
							else if (mouse.button === Qt.RightButton && p.canGoNext)
								p.next();
							else if (mouse.button === Qt.MiddleButton && p.canGoPrevious)
								p.previous();
						}
						onWheel: event => {
							const p = shellRoot.mediaPlayer;
							if (!p || !p.canSeek)
								return;
							// ±5s seek; position/length are seconds in Quickshell's MprisPlayer.
							if (event.angleDelta.y > 0)
								p.seek(5);
							else if (event.angleDelta.y < 0)
								p.seek(-5);
						}
					}
				}

				// StatusNotifier tray: collapses when empty so desktops without tray apps stay clean.
				Rectangle {
					visible: SystemTray.items.values.length > 0
					Layout.alignment: Qt.AlignVCenter
					radius: 8
					color: "#313244"
					implicitHeight: 24
					implicitWidth: trayRow.implicitWidth + 12

					Row {
						id: trayRow
						anchors.centerIn: parent
						spacing: 2

						// Chevron: left when collapsed (icons tuck leftward), right when expanded.
						MouseArea {
							implicitWidth: 16
							implicitHeight: 22
							acceptedButtons: Qt.LeftButton
							onClicked: shellRoot.trayCollapsed = !shellRoot.trayCollapsed

							Text {
								anchors.centerIn: parent
								color: "#6c7086"
								font.pixelSize: 12
								font.family: "IosevkaTermSlab NF"
								text: String.fromCodePoint(shellRoot.trayCollapsed ? 0xF0141 : 0xF0142)
							}
						}

						Text {
							visible: shellRoot.trayCollapsed
							anchors.verticalCenter: parent.verticalCenter
							color: "#6c7086"
							font.pixelSize: 11
							text: SystemTray.items.values.length
						}

						Repeater {
							model: shellRoot.trayCollapsed ? null : SystemTray.items

							delegate: MouseArea {
								id: trayDelegate
								required property var modelData

								implicitWidth: 22
								implicitHeight: 22
								acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
								hoverEnabled: true
								scrollGestureEnabled: true

								onClicked: mouse => {
									if (mouse.button === Qt.LeftButton) {
										if (modelData.onlyMenu) {
											trayMenu.open();
										} else {
											modelData.activate();
											// Activate only tells the app to show itself; it does not focus
											// or switch workspace. qs-tray-focus resolves the SNI id to a
											// Hyprland client and focuses it (polls briefly if the window
											// is still appearing).
											trayFocus.running = true;
										}
									} else if (mouse.button === Qt.RightButton) {
										trayMenu.open();
									} else if (mouse.button === Qt.MiddleButton) {
										modelData.secondaryActivate();
									}
								}
								onWheel: event => {
									modelData.scroll(event.angleDelta.y, false);
								}

								// Per-delegate so rapid clicks on different icons do not collide
								// (a shared Process only allows one run at a time).
								Process {
									id: trayFocus
									command: ["qs-tray-focus", trayDelegate.modelData.id]
								}

								// Rendered through MultiEffect, so the icon itself stays hidden and only
								// the desaturated/tinted copy is drawn (Qt texture provider pattern).
								IconImage {
									id: trayIcon
									anchors.centerIn: parent
									source: trayDelegate.modelData.icon
									implicitSize: 16
									visible: false
								}

								MultiEffect {
									anchors.fill: trayIcon
									source: trayIcon
									// Mild: colorful brand icons stay recognizable, symbolic ones blend
									// into the bar foreground.
									saturation: -0.8
									colorization: 0.6
									colorizationColor: "#cdd6f4"
								}

								QsMenuAnchor {
									id: trayMenu
									menu: trayDelegate.modelData.menu
									anchor.window: barWindow
									anchor.item: trayDelegate
									anchor.edges: Edges.Bottom
									anchor.gravity: Edges.Bottom
								}
							}
						}
					}
				}

				Rectangle {
					id: statusCluster
					radius: 8
					color: "#313244"
					implicitHeight: 24
					implicitWidth: statusClusterRow.implicitWidth + 10

					Row {
						id: statusClusterRow
						anchors.centerIn: parent
						spacing: 2

						MouseArea {
							id: nixosPill
							visible: shellRoot.nixosStatusVisible()
							implicitWidth: Math.max(22, nixosClusterRow.implicitWidth + 4)
							implicitHeight: 22
							hoverEnabled: true
							acceptedButtons: Qt.LeftButton | Qt.RightButton
							onClicked: mouse => {
								barWindow.disarmTip();
								if (mouse.modifiers & Qt.ShiftModifier)
									shellRoot.refreshNixosStatus(true);
								else if (mouse.button === Qt.LeftButton)
									Hyprland.dispatch("exec qs-nixos-term rebuild");
								else if (mouse.button === Qt.RightButton)
									Hyprland.dispatch("exec qs-nixos-term update");
							}
							onEntered: barWindow.armTip(nixosPill, "nixos")
							onExited: barWindow.disarmTip()

							Row {
								id: nixosClusterRow
								anchors.centerIn: parent
								spacing: 2

								Text {
									visible: shellRoot.nixosRebuildPending
									color: "#f9e2af"
									font.pixelSize: 14
									font.family: "IosevkaTermSlab NF"
									text: String.fromCodePoint(0xF05B7)
								}

								Text {
									visible: shellRoot.nixosUpdates > 0
									color: "#89b4fa"
									font.pixelSize: 14
									font.family: "IosevkaTermSlab NF"
									text: String.fromCodePoint(0xF06B0)
								}

								Text {
									visible: shellRoot.nixosUpdates > 0
									color: "#89b4fa"
									font.pixelSize: 12
									text: shellRoot.nixosUpdates
								}
							}
						}

						MouseArea {
							id: qsReloadPill
							visible: shellRoot.qsReloadPending
							implicitWidth: 22
							implicitHeight: 22
							hoverEnabled: true
							acceptedButtons: Qt.LeftButton
							onClicked: {
								barWindow.disarmTip();
								shellRoot.qsReloadPending = false;
								Hyprland.dispatch("exec qs-quickshell-reload");
							}
							onEntered: barWindow.armTip(qsReloadPill, "qsreload")
							onExited: barWindow.disarmTip()

							Text {
								anchors.centerIn: parent
								color: "#89b4fa"
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: String.fromCodePoint(0xF0453) // nf-md-refresh
							}
						}

						MouseArea {
							id: wifiPill
							implicitWidth: 22
							implicitHeight: 22
							hoverEnabled: true
							acceptedButtons: Qt.LeftButton | Qt.RightButton
							onClicked: mouse => {
								barWindow.disarmTip();
								if (mouse.button === Qt.LeftButton)
									Hyprland.dispatch("exec nmgui");
								else if (mouse.button === Qt.RightButton)
									Hyprland.dispatch("exec kitty --title nmtui nmtui");
							}
							onEntered: barWindow.armTip(wifiPill, "wifi")
							onExited: barWindow.disarmTip()

							Text {
								anchors.centerIn: parent
								color: shellRoot.networkColor()
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.networkIcon()
							}
						}

						MouseArea {
							id: btPill
							visible: shellRoot.btPresent
							implicitWidth: 22
							implicitHeight: 22
							hoverEnabled: true
							acceptedButtons: Qt.LeftButton | Qt.RightButton
							onClicked: mouse => {
								barWindow.disarmTip();
								if (mouse.button === Qt.LeftButton)
									Hyprland.dispatch("exec blueman-manager");
								else if (mouse.button === Qt.RightButton && shellRoot.btAdapter)
									shellRoot.btAdapter.enabled = !shellRoot.btAdapter.enabled;
							}
							onEntered: barWindow.armTip(btPill, "bt")
							onExited: barWindow.disarmTip()

							Text {
								anchors.centerIn: parent
								color: shellRoot.bluetoothColor()
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.bluetoothIcon()
							}
						}

						MouseArea {
							id: brightnessPill
							visible: shellRoot.brightnessPresent
							implicitWidth: 22
							implicitHeight: 22
							hoverEnabled: true
							acceptedButtons: Qt.LeftButton
							scrollGestureEnabled: true
							onClicked: {
								barWindow.disarmTip();
								shellRoot.cycleKbdBrightness();
							}
							onWheel: event => {
								if (event.angleDelta.y > 0)
									shellRoot.adjustBrightness(1);
								else if (event.angleDelta.y < 0)
									shellRoot.adjustBrightness(-1);
							}
							onEntered: barWindow.armTip(brightnessPill, "brightness")
							onExited: barWindow.disarmTip()

							Text {
								anchors.centerIn: parent
								color: "#f9e2af"
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.brightnessIcon()
							}
						}

						MouseArea {
							id: batteryPill
							visible: shellRoot.batteryPresent
							implicitWidth: Math.max(22, batteryClusterRow.implicitWidth + 4)
							implicitHeight: 22
							hoverEnabled: true
							acceptedButtons: Qt.LeftButton
							onClicked: {
								barWindow.disarmTip();
								shellRoot.cyclePowerProfile();
							}
							onEntered: barWindow.armTip(batteryPill, "battery")
							onExited: barWindow.disarmTip()

							Row {
								id: batteryClusterRow
								anchors.centerIn: parent
								spacing: 2

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
						}

						MouseArea {
							id: idlePill
							implicitWidth: 22
							implicitHeight: 22
							hoverEnabled: true
							acceptedButtons: Qt.LeftButton
							onClicked: {
								barWindow.disarmTip();
								shellRoot.idleInhibited = !shellRoot.idleInhibited;
							}
							onEntered: barWindow.armTip(idlePill, "idle")
							onExited: barWindow.disarmTip()

							Text {
								anchors.centerIn: parent
								color: shellRoot.idleInhibitColor()
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.idleInhibitIcon()
							}
						}

						MouseArea {
							id: micPill
							visible: shellRoot.micPresent
							implicitWidth: 22
							implicitHeight: 22
							hoverEnabled: true
							acceptedButtons: Qt.LeftButton | Qt.RightButton
							onClicked: mouse => {
								barWindow.disarmTip();
								if (mouse.button === Qt.LeftButton && shellRoot.micPresent)
									shellRoot.micSource.audio.muted = !shellRoot.micSource.audio.muted;
								else if (mouse.button === Qt.RightButton)
									Hyprland.dispatch("exec pavucontrol --tab=4");
							}
							onEntered: barWindow.armTip(micPill, "mic")
							onExited: barWindow.disarmTip()

							Text {
								anchors.centerIn: parent
								color: shellRoot.micColor()
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.micIcon()
							}
						}

						MouseArea {
							id: audioPill
							implicitWidth: 22
							implicitHeight: 22
							hoverEnabled: true
							acceptedButtons: Qt.LeftButton | Qt.RightButton
							scrollGestureEnabled: true
							onClicked: mouse => {
								barWindow.disarmTip();
								if (mouse.button === Qt.LeftButton)
									shellRoot.runAudioAction("pavu-toggle", false);
								else if (mouse.button === Qt.RightButton)
									shellRoot.runAudioAction("pamixer -t", true);
							}
							onWheel: event => {
								if (event.angleDelta.y > 0)
									shellRoot.runAudioAction("pamixer -i 1", true);
								else if (event.angleDelta.y < 0)
									shellRoot.runAudioAction("pamixer -d 1", true);
							}
							onEntered: barWindow.armTip(audioPill, "audio")
							onExited: barWindow.disarmTip()

							Text {
								anchors.centerIn: parent
								color: "#cdd6f4"
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.audioIcon()
							}
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

			PopupWindow {
				visible: barWindow.tipOn && barWindow.tipItem !== null
				grabFocus: false
				color: "transparent"
				implicitWidth: barTipText.implicitWidth + 16
				implicitHeight: barTipText.implicitHeight + 12
				anchor.window: barWindow
				anchor.item: barWindow.tipItem
				anchor.edges: Edges.Bottom
				anchor.gravity: Edges.Bottom

				Rectangle {
					anchors.fill: parent
					color: "#181825"
					radius: 8
					border.width: 1
					border.color: "#313244"

					Text {
						id: barTipText
						anchors.centerIn: parent
						color: "#cdd6f4"
						font.pixelSize: 12
						text: shellRoot.barTooltipText(barWindow.tipKind)
					}
				}
			}
		}
	}

	Component.onCompleted: {
		shellRoot.refreshBrightness();
		// Silent (no pill flash) so the first click cycles from the real level.
		shellRoot.refreshKbdBrightness();
		shellRoot.refreshNixosStatus(false);
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
			visible: isCenterScreen && shellRoot.osdVisible

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
						text: shellRoot.osdIcon()
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
							width: shellRoot.osdPercent() > 0 ? Math.max(6, Math.min(parent.width, parent.width * (shellRoot.osdPercent() / 100.0))) : 0
							height: parent.height
							radius: parent.radius
							color: shellRoot.osdFillColor()
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

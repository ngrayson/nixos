//@ pragma UseQApplication
// Required for system tray context menus (QsMenuAnchor.open needs QApplication mode).
// Quickshell: top bar (Hyprland workspaces + clock) + WlSessionLock (PAM password).
// One bar per output via `Variants` + `Quickshell.screens` (not follow-focus on a single PanelWindow).
// Lock: `quickshell ipc -p <live config> -n call lock activate` (see `quickshell-lock`).
// Preview (not a session lock, Esc dismisses): `ipc call lock preview` (see `quickshell-lock-preview`).
// Debug: `quickshell ipc -p ~/.config/quickshell show` (subcommand is `ipc`, not a bare `show` flag).
// Audio debug overlay: `quickshell ipc -p ~/.config/quickshell call audio toggleDebug`
// Power menu: `qs-quickshell-ipc call power toggle` (short XF86PowerOff; no-op while locked).
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
			return Theme.muted;
		if (micActive)
			return Theme.error;
		return Theme.text;
	}

	// Wayland idle-inhibit: when true, hypridle (ignore_dbus_inhibit=false) will not
	// lock/suspend. Bound to each bar PanelWindow below.
	property bool idleInhibited: false

	// Fullscreen overlay that looks like the lock but is not WlSessionLock. Esc dismisses.
	property bool lockPreview: false

	// Centered power menu (sleep / hibernate / restart / shutdown). Esc dismisses.
	property bool powerMenuVisible: false

	// Hyprland's resize-move mode (SUPER+A). While it is on, a bare left-drag
	// moves windows and a bare right-drag resizes them, so knowing it is on is
	// not cosmetic -- ordinary clicking behaves differently everywhere.
	//
	// State is PUSHED by hypr-resize-move-toggle over IPC rather than polled:
	// that script is the only thing that enters or leaves the mode, so it knows
	// each transition exactly and there is nothing to poll for. If the bar is
	// restarted while the mode is active the pill will be missing, but the
	// script's dead-man timer clears the mode within its timeout regardless --
	// the indicator can go stale, the compositor state cannot.
	property bool resizeMoveActive: false
	property int resizeMoveRemaining: 0

	// Screen warmth. Published by hypr-sunset-apply once per tick; the bar only
	// ever displays it and shells out to hypr-sunset-ctl to change it. The
	// scheduler is the single writer of the colour transform matrix -- see
	// home/services/hyprsunset.nix.
	property var sunsetState: ({})
	property bool sunsetMenuVisible: false

	readonly property string sunsetRuntimeDir: `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr-sunset`

	function sunsetOk(): bool {
		return (shellRoot.sunsetState?.ok ?? false) === true;
	}

	function sunsetPhase(): string {
		return shellRoot.sunsetState?.phase ?? "";
	}

	function sunsetIcon(): string {
		const phase = shellRoot.sunsetPhase();
		// A discrete change (toggle, pause, settings edit) eases over a few
		// seconds; show it moving rather than sitting on the destination icon.
		if (shellRoot.sunsetState?.ramping === true)
			return String.fromCodePoint(0xF059A); // nf-md-weather_sunset
		if (phase === "off")
			return String.fromCodePoint(0xF14E4); // nf-md-weather_sunny_off
		if (phase === "night")
			return String.fromCodePoint(0xF0594); // nf-md-weather_night
		if (phase === "to-night")
			return String.fromCodePoint(0xF059B); // nf-md-weather_sunset_down
		if (phase === "to-day")
			return String.fromCodePoint(0xF059C); // nf-md-weather_sunset_up
		return String.fromCodePoint(0xF0599); // nf-md-weather_sunny
	}

	function sunsetColor(): string {
		const phase = shellRoot.sunsetPhase();
		if (phase === "off")
			return Theme.muted;
		if (phase === "to-night" || phase === "to-day")
			return Theme.accent;
		return Theme.text;
	}

	function sunsetClock(epoch): string {
		if (!epoch)
			return "--:--";
		return Qt.formatTime(new Date(epoch * 1000), "HH:mm");
	}

	function sunsetUntilText(): string {
		const st = shellRoot.sunsetState;
		const next = st?.nextEvent ?? 0;
		const now = st?.now ?? 0;
		if (!next || !now)
			return "";
		const mins = Math.max(0, Math.round((next - now) / 60));
		const h = Math.floor(mins / 60);
		const m = mins % 60;
		const span = h > 0 ? (h + "h " + m + "m") : (m + "m");
		return span + " to " + (st?.nextKind ?? "sunset");
	}

	function sunsetTooltipText(): string {
		const st = shellRoot.sunsetState;
		if (!shellRoot.sunsetOk()) {
			const reason = st?.reason ?? "starting up";
			return "Screen warmth idle · " + (reason === "no-location" ? "waiting on a location fix" : reason);
		}
		const lines = [];
		if (shellRoot.sunsetPhase() === "off") {
			const until = st?.disabledUntil ?? 0;
			lines.push(until > 0 ? ("Screen warmth paused until " + shellRoot.sunsetClock(until)) : "Screen warmth off");
		} else {
			lines.push("Screen warmth " + (st?.temp ?? "--") + "K · gamma " + (st?.gamma ?? "--") + "%");
		}
		lines.push("Night " + (st?.nightTemp ?? "--") + "K · gamma " + (st?.nightGamma ?? "--") + "%");
		lines.push("Sunrise " + shellRoot.sunsetClock(st?.sunrise ?? 0) + " · sunset " + shellRoot.sunsetClock(st?.sunset ?? 0));
		const until = shellRoot.sunsetUntilText();
		if (until)
			lines.push(until + " · ramp " + (st?.transitionMin ?? "--") + " min");
		lines.push("Left-click pauses/resumes · right-click for options");
		return lines.join("\n");
	}

	function resizeMoveTooltipText(): string {
		return "Resize/move mode on · bare left-drag moves, right-drag resizes"
			+ "\nExits " + resizeMoveRemaining + "s after you stop moving, or on Escape / Super+A";
	}

	// Tray icons hidden behind a chevron; the pill keeps the chevron + item count.
	property bool trayCollapsed: false

	// One entry per plugged-in removable USB disk, from qs-usb-status. Empty
	// (and the cluster hidden) whenever nothing mountable is plugged in.
	property var usbDevices: []

	// Hidden while the running system matches the flake and flake.lock is current.
	property bool nixosRebuildPending: false
	property int nixosUpdates: 0
	property int nixosRepoBehind: 0
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
		return nixosRebuildPending || nixosUpdates > 0 || nixosRepoBehind > 0;
	}

	function refreshNixosStatus(force: bool): void {
		if (readNixosStatus.running)
			return;
		const args = ["qs-nixos-status"];
		if (force)
			args.push("--force");
		if (networkKind === "wifi" || networkKind === "wired")
			args.push("--online");
		readNixosStatus.command = args;
		readNixosStatus.running = true;
	}

	function refreshUsbStatus(): void {
		if (readUsbStatus.running)
			return;
		readUsbStatus.running = true;
	}

	function usbTooltipText(device): string {
		if (!device)
			return "";
		const lines = [];
		const size = device.size ? " · " + device.size : "";
		lines.push((device.label || "USB") + size);
		const parts = device.partitions || [];
		for (let i = 0; i < parts.length; i++) {
			const p = parts[i];
			if (p.mountpoint)
				lines.push(p.mountpoint + (p.fstype ? " (" + p.fstype + ")" : ""));
		}
		if (!device.anyMounted)
			lines.push("Not mounted");
		lines.push(device.anyBusy ? "In use" : "Safe to remove");
		lines.push("Left-click: open in Dolphin");
		lines.push("Right-click: eject");
		return lines.join("\n");
	}

	function nixosTooltipText(): string {
		const lines = [];
		if (nixosRepoBehind > 0)
			lines.push("Repo: " + nixosRepoBehind + " commit" + (nixosRepoBehind === 1 ? "" : "s") + " on origin not pulled");
		if (nixosRebuildPending)
			lines.push("Wrench: flake config is not what this machine is running");
		if (nixosUpdates > 0)
			lines.push("Updates: " + nixosUpdates + " flake input" + (nixosUpdates === 1 ? "" : "s") + " newer than flake.lock");
		if (nixosRepoBehind > 0)
			lines.push("Left-click: git pull");
		else
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

	function trayTooltipText(item): string {
		if (!item)
			return "Tray app";
		const tooltipTitle = String(item.tooltipTitle || "").trim();
		const title = String(item.title || "").trim();
		const nameLine = tooltipTitle || title || "Tray app";
		const lines = [nameLine];
		const description = String(item.tooltipDescription || "").trim();
		if (description !== "" && description !== nameLine)
			lines.push(description);
		if (item.status === Status.NeedsAttention)
			lines.push("Needs attention");
		if (item.onlyMenu)
			lines.push("Left-click: menu");
		else
			lines.push("Left-click: show window");
		if (item.hasMenu)
			lines.push("Right-click: menu");
		return lines.join("\n");
	}

	function barTooltipText(kind: string, trayItem): string {
		// trayItem is the generic hover payload: an SNI item for "tray", the
		// device object for "usb".
		if (kind === "usb")
			return usbTooltipText(trayItem);
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
		if (kind === "resizemove")
			return resizeMoveTooltipText();
		if (kind === "sunset")
			return sunsetTooltipText();
		if (kind === "mic")
			return micTooltipText();
		if (kind === "audio")
			return audioTooltipText();
		if (kind === "power")
			return "Power";
		if (kind === "tray")
			return trayTooltipText(trayItem);
		return "";
	}

	function idleInhibitIcon(): string {
		return String.fromCodePoint(0xEC15); // nf-cod-flame
	}

	function idleInhibitColor(): string {
		return idleInhibited ? Theme.bright : Theme.muted;
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
			return Theme.selection;
		if (networkKind === "disconnected" || networkKind === "off")
			return Theme.muted;
		return Theme.text;
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
			return Theme.selection;
		if (!btEnabled || btBlocked)
			return Theme.muted;
		if (btConnectedCount > 0)
			return Theme.accent;
		return Theme.text;
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
			return Theme.bright;
		if (debugAudio)
			return Theme.sage;
		if (audioMuted)
			return Theme.muted;
		return Theme.accent;
	}

	// The output that owns the lock prompt, the power menu and the sunset modal
	// -- and, via blankSideMonitors(), the one output that stays lit while the
	// session is locked.
	//
	// Focus first, geometry second. The midpoint heuristic alone put the lock
	// prompt on whichever panel happened to sit in the middle of the desktop
	// (HDMI-A-1 on Tawa), not the monitor being worked at. Geometry remains the
	// fallback for the cases where there is no focused monitor to ask about.
	//
	// This is the SINGLE definition of "centre". hypr-dpms-side-off used to
	// recompute it from `hyprctl monitors -j`, whose width/height are
	// pre-transform where Quickshell.screens are post-transform -- two answers
	// that agreed on Tawa's layout only by luck. The name is passed to the
	// script now; nothing else may derive it.
	function centerOutputScreen(): var {
		const screens = Quickshell.screens;
		const n = screens.length;
		if (n === 0)
			return null;
		if (n === 1)
			return screens[0];

		const focusedName = Hyprland.focusedMonitor?.name ?? "";
		if (focusedName) {
			for (let i = 0; i < n; ++i) {
				if (screens[i].name === focusedName)
					return screens[i];
			}
		}

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
			else {
				sessionLock.locked = false;
				shellRoot.restoreSideMonitors();
			}
		}
	}

	Process {
		id: sideDpmsOff
		running: false
	}

	Process {
		id: sideDpmsOn
		running: false
		command: ["hypr-dpms-side-on"]
	}

	// The keep-lit output is resolved here, at call time, and handed to the
	// script -- see centerOutputScreen(). An empty name makes the script blank
	// nothing, which is the correct way to fail: the alternative is a locked
	// machine with every screen dark.
	function blankSideMonitors(): void {
		if (sideDpmsOff.running)
			sideDpmsOff.running = false;
		sideDpmsOff.command = ["hypr-dpms-side-off", shellRoot.centerOutputScreen()?.name ?? ""];
		sideDpmsOff.running = true;
	}

	function restoreSideMonitors(): void {
		if (sideDpmsOn.running)
			sideDpmsOn.running = false;
		sideDpmsOn.running = true;
	}

	WlSessionLock {
		id: sessionLock
		locked: false

		WlSessionLockSurface {
			id: lockSessionSurface
			// Chrome on EVERY output, not just the center one. activate() below
			// DPMS-blanks the sides, so a prompt on the geometric centre alone
			// means any monitor the user wakes by hand shows bare wallpaper with
			// no way to type a password — observed on Tawa 2026-09-02, where
			// recovery was `hyprctl dispatch dpms on` from another machine.
			//
			// This is cheap because lockContext is a single shared object: every
			// surface already mirrors the same typed text and the same failure
			// shake through LockSurface's Connections on context.currentText.
			// Keyboard focus still lands on exactly one surface — `primary`.
			readonly property bool isPrimaryOutput: {
				const c = shellRoot.centerOutputScreen();
				return c && screen && c.name === screen.name;
			}

			color: Theme.bg

			LockSurface {
				anchors.fill: parent
				context: lockContext
				preview: false
				showUi: true
				primary: lockSessionSurface.isPrimaryOutput
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
			color: Theme.bg
			exclusionMode: ExclusionMode.Ignore
			// Every preview surface is focusable, not just the center one.
			// Previously the other outputs showed full-screen lock chrome while
			// accepting no keyboard focus at all, so they looked like a stuck
			// lock screen with no way out. Exclusive stays on the center surface
			// only -- an exclusive grab on every output at once trades this bug
			// for a worse one.
			focusable: previewOpen

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "qs-lock-preview-" + modelData.name
			WlrLayershell.keyboardFocus: previewOpen ? (isCenterScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand) : WlrKeyboardFocus.None

			anchors.top: true
			anchors.bottom: true
			anchors.left: true
			anchors.right: true

			LockSurface {
				anchors.fill: parent
				context: lockContext
				preview: true
				showUi: previewWin.previewOpen && previewWin.isCenterScreen
				// showUi draws the chrome; primary takes the keystrokes. Only
				// the center surface needs either. Esc is deliberately NOT gated
				// on them -- see the Shortcut in LockSurface.qml.
				primary: previewWin.isCenterScreen
				onDismissRequested: shellRoot.lockPreview = false
			}
		}
	}

	// Backstop: the preview clears itself after two minutes. Esc widened to
	// every output above is the intended exit, but a layer-shell surface only
	// receives keys once the compositor has given it focus, so "press Esc" is
	// not a guarantee on an output the user never clicked. This is, and it is
	// why the card asked for both.
	//
	// Bound to `running` rather than started and stopped inside preview() /
	// cancelPreview() / onUnlocked: every path that clears lockPreview --
	// including onDismissRequested and activate() -- stops it for free, and a
	// fresh preview restarts the full interval. Three manual call sites would
	// be three chances to miss one.
	//
	// The preview holds no ext-session-lock and protects nothing, so a timeout
	// here is not a security property. Never give the real WlSessionLock one.
	Timer {
		interval: 120000
		repeat: false
		running: shellRoot.lockPreview
		onTriggered: shellRoot.lockPreview = false
	}

	IpcHandler {
		target: "lock"

		// Return type required or quickshell will not register this for `ipc call lock activate`.
		function activate(): void {
			shellRoot.lockPreview = false;
			lockContext.currentText = "";
			sessionLock.locked = true;
			// Match the SDDM greeter: keep the center panel lit, blank the sides.
			shellRoot.blankSideMonitors();
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

	// Driven by hypr-resize-move-toggle on every transition, including the
	// dead-man timeout firing. Both calls are best-effort on the script side:
	// the mode must work with the bar dead.
	IpcHandler {
		target: "resizemove"

		// Return type required or quickshell will not register this for
		// `ipc call resizemove enter`.
		// Called once per second while the mode is on, not once at entry: the
		// deadline is idle-based, so the number resets upward whenever the
		// cursor moves. The script owns all timing; the bar only displays.
		function enter(seconds: string): void {
			const parsed = parseInt(seconds, 10);
			shellRoot.resizeMoveRemaining = isNaN(parsed) ? 0 : parsed;
			shellRoot.resizeMoveActive = true;
			resizeMoveStaleTimer.restart();
		}

		function leave(): void {
			resizeMoveStaleTimer.stop();
			shellRoot.resizeMoveActive = false;
			shellRoot.resizeMoveRemaining = 0;
		}
	}

	// Staleness watchdog, not a countdown. The bar must never decrement on its
	// own: the deadline is idle-based, so the pushed value climbs back up every
	// time the cursor moves, and a local decrement would fight it -- worse, a
	// self-clear at zero would hide a mode that is genuinely still on. This
	// fires only when the pushes stop without a `leave` arriving (script
	// killed, socket hiccup), where a pill that vanishes a beat early beats one
	// stuck forever claiming a mode that is not active.
	Timer {
		id: resizeMoveStaleTimer
		interval: 3000
		repeat: false
		onTriggered: {
			shellRoot.resizeMoveActive = false;
			shellRoot.resizeMoveRemaining = 0;
		}
	}

	IpcHandler {
		target: "power"

		// Return type required or quickshell will not register this for `ipc call power toggle`.
		function toggle(): void {
			if (sessionLock.locked)
				return;
			shellRoot.powerMenuVisible = !shellRoot.powerMenuVisible;
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

	FileView {
		path: `${shellRoot.qsSourceDir}/PowerMenu.qml`
		watchChanges: true
		printErrors: false
		onFileChanged: shellRoot.markQsReloadPending()
	}

	FileView {
		path: `${shellRoot.qsSourceDir}/SunsetMenu.qml`
		watchChanges: true
		printErrors: false
		onFileChanged: shellRoot.markQsReloadPending()
	}

	// The scheduler rewrites this once per tick (atomically, via rename), so
	// watching it is cheaper and more accurate than polling hyprsunset. Absent
	// or malformed is normal at login before the first tick: leave the previous
	// value rather than blanking the pill.
	FileView {
		id: sunsetStateFile
		path: `${shellRoot.sunsetRuntimeDir}/state.json`
		watchChanges: true
		printErrors: false

		// Named parseState, not reload: FileView already has a reload() and
		// shadowing it here would recurse.
		function parseState(): void {
			const raw = sunsetStateFile.text();
			if (!raw)
				return;
			try {
				shellRoot.sunsetState = JSON.parse(raw);
			} catch (e) {
				// Mid-write or truncated; the next tick brings a whole file.
			}
		}

		onLoaded: sunsetStateFile.parseState()
		onFileChanged: sunsetStateFile.reload()
	}

	Timer {
		interval: 1500
		running: true
		repeat: false
		onTriggered: shellRoot.qsReloadWatchArmed = true
	}

	Process {
		id: readUsbStatus
		running: false
		command: ["qs-usb-status"]

		stdout: StdioCollector {
			onStreamFinished: {
				const raw = this.text.trim();
				try {
					const data = JSON.parse(raw || "[]");
					shellRoot.usbDevices = Array.isArray(data) ? data : [];
				} catch (_e) {
					// Keep the previous list rather than blanking the cluster on
					// one malformed read.
				}
			}
		}
	}

	// lsblk + fuser are cheap, and 5s keeps the "in use" state fresh enough to
	// trust before pulling a drive.
	Timer {
		interval: 5000
		running: true
		repeat: true
		triggeredOnStart: true
		onTriggered: shellRoot.refreshUsbStatus()
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
					shellRoot.nixosRepoBehind = Number(data.behind) || 0;
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
			color: Theme.depth

			property Item tipItem: null
			property string tipKind: ""
			property var tipTray: null
			property bool tipOn: false

			function armTip(item, kind: string, trayItem): void {
				tipItem = item;
				tipKind = kind;
				tipTray = trayItem ?? null;
				tipDelay.restart();
			}

			function disarmTip(): void {
				tipDelay.stop();
				tipOn = false;
				tipTray = null;
			}

			Timer {
				id: tipDelay
				interval: 400
				repeat: false
				onTriggered: barWindow.tipOn = true
			}

			// Icon-sized defaults over the shared chrome (BarHoverArea.qml): the
			// status cluster is a row of 22x22 squares and every one of them arms the
			// bar tooltip, so those two things live here rather than in the shared
			// component, which stays size- and host-agnostic for wider widgets.
			component StatusPill: BarHoverArea {
				implicitWidth: 22
				implicitHeight: 22
				tipHost: barWindow
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
						id: wsPill
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
						color: isFocused ? Theme.border : (occupied ? Theme.surface : "transparent")

						// The number lives inside the hover area so the press-squish takes
						// it along; the pill's own focused/occupied background stays put.
						BarHoverArea {
							anchors.fill: parent
							radius: 6
							acceptedButtons: Qt.LeftButton
							onClicked: Hyprland.dispatch("workspace " + wsPill.wid)

							Text {
								id: wsLabel
								anchors.centerIn: parent
								text: wsPill.wid
								color: (wsPill.isFocused || wsPill.occupied) ? Theme.text : Theme.muted
								font.pixelSize: 14
							}
						}
					}
				}

				Item {
					Layout.fillWidth: true
				}

				Text {
					visible: shellRoot.debugAudio
					Layout.alignment: Qt.AlignVCenter
					color: Theme.selection
					font.pixelSize: 9
					text: shellRoot.audioPercent + "% m=" + shellRoot.audioMuted + " ex=" + shellRoot.audioLastExitCode
				}

				Rectangle {
					visible: shellRoot.mediaPresent
					radius: 8
					color: Theme.surface
					implicitHeight: 24
					implicitWidth: mediaRow.implicitWidth + 16

					// mediaRow moved inside the hover area rather than beside it, so the
					// press-squish takes the icon and label with it. The plain MouseArea
					// this replaces had no cursor, highlight or press feedback at all.
					BarHoverArea {
						anchors.fill: parent
						radius: 8
						acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
						scrollGestureEnabled: true

						RowLayout {
							id: mediaRow
							anchors.centerIn: parent
							spacing: 4

							Text {
								color: shellRoot.mediaPlayer?.isPlaying ? Theme.sage : Theme.text
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.mediaIcon()
							}

							Text {
								color: Theme.text
								font.pixelSize: 12
								text: shellRoot.mediaLabel()
							}
						}
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
				// Removable USB disks: one pill per physical disk, right-click ejects.
				Rectangle {
					visible: shellRoot.usbDevices.length > 0
					Layout.alignment: Qt.AlignVCenter
					radius: 8
					color: Theme.surface
					implicitHeight: 24
					implicitWidth: usbRow.implicitWidth + 12

					Row {
						id: usbRow
						anchors.centerIn: parent
						spacing: 2

						Repeater {
							model: shellRoot.usbDevices

							delegate: StatusPill {
								id: usbPill
								required property var modelData

								tipKind: "usb"
								acceptedButtons: Qt.LeftButton | Qt.RightButton
								// StatusPill arms the tip without a payload, so re-arm
								// with this device attached.
								onEntered: barWindow.armTip(usbPill, "usb", usbPill.modelData)
								onClicked: mouse => {
									if (mouse.button === Qt.LeftButton) {
										barWindow.disarmTip();
										// Hyprland.dispatch, not a Process: Dolphin must
										// outlive the bar, and this is how the other pills
										// launch GUI apps.
										Hyprland.dispatch("exec qs-usb-open " + usbPill.modelData.disk);
										return;
									}
									if (mouse.button !== Qt.RightButton)
										return;
									barWindow.disarmTip();
									usbEject.running = true;
								}

								// Per-delegate so ejecting two drives in quick succession
								// does not collide (a shared Process runs one at a time).
								Process {
									id: usbEject
									running: false
									command: ["qs-usb-eject", usbPill.modelData.disk]
									onExited: exitCode => {
										// Refresh either way: on success the pill should
										// vanish now, on failure the busy state may have
										// changed under us.
										shellRoot.refreshUsbStatus();
									}
								}

								Text {
									anchors.centerIn: parent
									color: usbPill.modelData.anyBusy ? Theme.muted : Theme.text
									font.pixelSize: 12
									font.family: "IosevkaTermSlab NF"
									// md-eject. Verified by glyph NAME in the installed font,
									// not just by the codepoint being mapped: 0xF0158 is
									// md-close_box_outline and rendered a close box here.
									text: String.fromCodePoint(0xF01EA)
								}
							}
						}
					}
				}

				Rectangle {
					visible: SystemTray.items.values.length > 0
					Layout.alignment: Qt.AlignVCenter
					radius: 8
					color: Theme.surface
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
							onClicked: {
								barWindow.disarmTip();
								shellRoot.trayCollapsed = !shellRoot.trayCollapsed;
							}

							Text {
								anchors.centerIn: parent
								color: Theme.muted
								font.pixelSize: 12
								font.family: "IosevkaTermSlab NF"
								text: String.fromCodePoint(shellRoot.trayCollapsed ? 0xF0141 : 0xF0142)
							}
						}

						Text {
							visible: shellRoot.trayCollapsed
							anchors.verticalCenter: parent.verticalCenter
							color: Theme.muted
							font.pixelSize: 11
							text: SystemTray.items.values.length
						}

						Repeater {
							model: shellRoot.trayCollapsed ? null : SystemTray.items

							delegate: StatusPill {
								id: trayDelegate
								required property var modelData

								acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
								scrollGestureEnabled: true

								// StatusPill arms the tip without a payload, so re-arm with this
								// tray item attached.
								onEntered: barWindow.armTip(trayDelegate, "tray", modelData)
								onExited: barWindow.disarmTip()
								onClicked: mouse => {
									barWindow.disarmTip();
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
									colorizationColor: Theme.text
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
					color: Theme.surface
					implicitHeight: 24
					implicitWidth: statusClusterRow.implicitWidth + 10

					Row {
						id: statusClusterRow
						anchors.centerIn: parent
						spacing: 2

						StatusPill {
							id: nixosPill
							visible: shellRoot.nixosStatusVisible()
							implicitWidth: Math.max(22, nixosClusterRow.implicitWidth + 4)
							tipKind: "nixos"
							acceptedButtons: Qt.LeftButton | Qt.RightButton
							onClicked: mouse => {
								barWindow.disarmTip();
								if (mouse.modifiers & Qt.ShiftModifier)
									shellRoot.refreshNixosStatus(true);
								else if (mouse.button === Qt.LeftButton && shellRoot.nixosRepoBehind > 0)
									Hyprland.dispatch("exec qs-nixos-term pull");
								else if (mouse.button === Qt.LeftButton)
									Hyprland.dispatch("exec qs-nixos-term rebuild");
								else if (mouse.button === Qt.RightButton)
									Hyprland.dispatch("exec qs-nixos-term update");
							}

							Row {
								id: nixosClusterRow
								anchors.centerIn: parent
								spacing: 2

								Text {
									visible: shellRoot.nixosRepoBehind > 0
									color: Theme.accent
									font.pixelSize: 14
									font.family: "IosevkaTermSlab NF"
									text: String.fromCodePoint(0xF01DA)
								}

								Text {
									visible: shellRoot.nixosRepoBehind > 0
									color: Theme.accent
									font.pixelSize: 12
									text: shellRoot.nixosRepoBehind
								}

								Text {
									visible: shellRoot.nixosRebuildPending
									color: Theme.bright
									font.pixelSize: 14
									font.family: "IosevkaTermSlab NF"
									text: String.fromCodePoint(0xF05B7)
								}

								Text {
									visible: shellRoot.nixosUpdates > 0
									color: Theme.accent
									font.pixelSize: 14
									font.family: "IosevkaTermSlab NF"
									text: String.fromCodePoint(0xF06B0)
								}

								Text {
									visible: shellRoot.nixosUpdates > 0
									color: Theme.accent
									font.pixelSize: 12
									text: shellRoot.nixosUpdates
								}
							}
						}

						StatusPill {
							id: qsReloadPill
							visible: shellRoot.qsReloadPending
							tipKind: "qsreload"
							acceptedButtons: Qt.LeftButton
							onClicked: {
								barWindow.disarmTip();
								shellRoot.qsReloadPending = false;
								Hyprland.dispatch("exec qs-quickshell-reload");
							}

							Text {
								anchors.centerIn: parent
								color: Theme.accent
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: String.fromCodePoint(0xF0453) // nf-md-refresh
							}
						}

						StatusPill {
							id: wifiPill
							tipKind: "wifi"
							acceptedButtons: Qt.LeftButton | Qt.RightButton
							onClicked: mouse => {
								barWindow.disarmTip();
								if (mouse.button === Qt.LeftButton)
									Hyprland.dispatch("exec nmgui");
								else if (mouse.button === Qt.RightButton)
									Hyprland.dispatch("exec kitty --title nmtui nmtui");
							}

							Text {
								anchors.centerIn: parent
								color: shellRoot.networkColor()
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.networkIcon()
							}
						}

						StatusPill {
							id: btPill
							visible: shellRoot.btPresent
							tipKind: "bt"
							acceptedButtons: Qt.LeftButton | Qt.RightButton
							onClicked: mouse => {
								barWindow.disarmTip();
								if (mouse.button === Qt.LeftButton)
									Hyprland.dispatch("exec blueman-manager");
								else if (mouse.button === Qt.RightButton && shellRoot.btAdapter)
									shellRoot.btAdapter.enabled = !shellRoot.btAdapter.enabled;
							}

							Text {
								anchors.centerIn: parent
								color: shellRoot.bluetoothColor()
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.bluetoothIcon()
							}
						}

						StatusPill {
							id: sunsetPill
							// Hidden until the scheduler has published a real
							// state, so a machine with no location fix shows
							// nothing rather than a pill that does nothing.
							visible: shellRoot.sunsetOk()
							tipKind: "sunset"
							acceptedButtons: Qt.LeftButton | Qt.RightButton
							onClicked: mouse => {
								barWindow.disarmTip();
								if (mouse.button === Qt.LeftButton)
									Hyprland.dispatch("exec hypr-sunset-ctl toggle");
								else if (mouse.button === Qt.RightButton)
									shellRoot.sunsetMenuVisible = !shellRoot.sunsetMenuVisible;
							}

							Text {
								anchors.centerIn: parent
								color: shellRoot.sunsetColor()
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.sunsetIcon()
							}
						}

						StatusPill {
							id: brightnessPill
							visible: shellRoot.brightnessPresent
							tipKind: "brightness"
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

							Text {
								anchors.centerIn: parent
								color: Theme.bright
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.brightnessIcon()
							}
						}

						StatusPill {
							id: batteryPill
							visible: shellRoot.batteryPresent
							implicitWidth: Math.max(22, batteryClusterRow.implicitWidth + 4)
							tipKind: "battery"
							acceptedButtons: Qt.LeftButton
							onClicked: {
								barWindow.disarmTip();
								shellRoot.cyclePowerProfile();
							}

							Row {
								id: batteryClusterRow
								anchors.centerIn: parent
								spacing: 2

								Text {
									color: shellRoot.batteryLow ? Theme.error : (shellRoot.batteryCharging ? Theme.sage : Theme.text)
									font.pixelSize: 14
									font.family: "IosevkaTermSlab NF"
									text: shellRoot.batteryIcon()
								}

								Text {
									color: shellRoot.batteryLow ? Theme.error : Theme.text
									font.pixelSize: 12
									text: shellRoot.batteryPercent + "%"
								}

								Text {
									visible: shellRoot.powerProfileMarked
									color: shellRoot.powerProfile === PowerProfile.PowerSaver ? Theme.sage : Theme.selection
									font.pixelSize: 14
									font.family: "IosevkaTermSlab NF"
									text: shellRoot.powerProfileIcon()
								}
							}
						}

						// Only visible while the mode is on -- an always-present
						// pill would defeat the point, which is answering "is it
						// on?" at a glance.
						StatusPill {
							id: resizeMovePill
							visible: shellRoot.resizeMoveActive
							implicitWidth: Math.max(22, resizeMoveRow.implicitWidth + 4)
							tipKind: "resizemove"
							acceptedButtons: Qt.LeftButton
							onClicked: {
								barWindow.disarmTip();
								Hyprland.dispatch("exec hypr-resize-move-toggle");
							}

							Row {
								id: resizeMoveRow
								anchors.centerIn: parent
								spacing: 2

								Text {
									color: Theme.bright
									font.pixelSize: 14
									font.family: "IosevkaTermSlab NF"
									text: String.fromCodePoint(0xF0A68)
								}

								Text {
									color: Theme.bright
									font.pixelSize: 12
									text: shellRoot.resizeMoveRemaining + "s"
								}
							}
						}

						StatusPill {
							id: idlePill
							tipKind: "idle"
							acceptedButtons: Qt.LeftButton
							onClicked: {
								barWindow.disarmTip();
								shellRoot.idleInhibited = !shellRoot.idleInhibited;
							}

							Text {
								anchors.centerIn: parent
								color: shellRoot.idleInhibitColor()
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.idleInhibitIcon()
							}
						}

						StatusPill {
							id: micPill
							visible: shellRoot.micPresent
							tipKind: "mic"
							acceptedButtons: Qt.LeftButton | Qt.RightButton
							onClicked: mouse => {
								barWindow.disarmTip();
								if (mouse.button === Qt.LeftButton && shellRoot.micPresent)
									shellRoot.micSource.audio.muted = !shellRoot.micSource.audio.muted;
								else if (mouse.button === Qt.RightButton)
									Hyprland.dispatch("exec pavucontrol --tab=4");
							}

							Text {
								anchors.centerIn: parent
								color: shellRoot.micColor()
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.micIcon()
							}
						}

						StatusPill {
							id: audioPill
							tipKind: "audio"
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

							Text {
								anchors.centerIn: parent
								color: Theme.text
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: shellRoot.audioIcon()
							}
						}

						StatusPill {
							id: powerPill
							tipKind: "power"
							onClicked: {
								barWindow.disarmTip();
								shellRoot.powerMenuVisible = !shellRoot.powerMenuVisible;
							}

							Text {
								anchors.centerIn: parent
								color: Theme.text
								font.pixelSize: 14
								font.family: "IosevkaTermSlab NF"
								text: String.fromCodePoint(0xF0425)
							}
						}
					}
				}

				Text {
					id: clockLabel
					color: Theme.text
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
					color: Theme.bg
					radius: 8
					border.width: 1
					border.color: Theme.surface

					Text {
						id: barTipText
						anchors.centerIn: parent
						color: Theme.text
						font.pixelSize: 12
						wrapMode: Text.Wrap
						width: Math.min(360, implicitWidth)
						text: {
							const tray = barWindow.tipTray;
							// These reads exist only to make the binding depend on the
							// SNI item's properties; they are meaningless for the "usb"
							// payload, which is a plain object.
							if (tray && barWindow.tipKind === "tray") {
								void tray.title;
								void tray.tooltipTitle;
								void tray.tooltipDescription;
								void tray.status;
							}
							return shellRoot.barTooltipText(barWindow.tipKind, tray);
						}
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
			id: powerMenuWin
			required property var modelData
			readonly property bool isCenterScreen: {
				const c = shellRoot.centerOutputScreen();
				return c && modelData && c.name === modelData.name;
			}
			readonly property bool menuOpen: shellRoot.powerMenuVisible

			screen: modelData
			visible: menuOpen && isCenterScreen
			color: "transparent"
			exclusionMode: ExclusionMode.Ignore
			focusable: menuOpen && isCenterScreen

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "qs-power-menu-" + modelData.name
			WlrLayershell.keyboardFocus: (menuOpen && isCenterScreen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

			anchors.top: true
			anchors.bottom: true
			anchors.left: true
			anchors.right: true

			PowerMenu {
				anchors.fill: parent
				active: powerMenuWin.menuOpen && powerMenuWin.isCenterScreen
				onDismissed: shellRoot.powerMenuVisible = false
			}
		}
	}

	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: sunsetMenuWin
			required property var modelData
			readonly property bool isCenterScreen: {
				const c = shellRoot.centerOutputScreen();
				return c && modelData && c.name === modelData.name;
			}
			readonly property bool menuOpen: shellRoot.sunsetMenuVisible

			screen: modelData
			visible: menuOpen && isCenterScreen
			color: "transparent"
			exclusionMode: ExclusionMode.Ignore
			focusable: menuOpen && isCenterScreen

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "qs-sunset-menu-" + modelData.name
			WlrLayershell.keyboardFocus: (menuOpen && isCenterScreen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

			anchors.top: true
			anchors.bottom: true
			anchors.left: true
			anchors.right: true

			SunsetMenu {
				anchors.fill: parent
				active: sunsetMenuWin.menuOpen && sunsetMenuWin.isCenterScreen
				state: shellRoot.sunsetState
				onDismissed: shellRoot.sunsetMenuVisible = false
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
			visible: isCenterScreen && shellRoot.osdVisible

			anchors.top: true
			anchors.bottom: true
			anchors.left: true
			anchors.right: true

			Rectangle {
				width: 250
				height: shellRoot.debugAudio ? 118 : 88
				radius: 12
				color: Theme.depth
				border.width: 1
				border.color: Theme.border
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
						color: Theme.text
						font.pixelSize: 20
						font.family: "IosevkaTermSlab NF"
					}

					Rectangle {
						id: osdMeter
						Layout.fillWidth: true
						Layout.preferredHeight: 8
						radius: 4
						color: Theme.surface

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
						color: Theme.selection
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

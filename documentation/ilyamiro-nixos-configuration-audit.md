# Audit: [ilyamiro/nixos-configuration](https://github.com/ilyamiro/nixos-configuration) vs this system

**This system:** `~/.config/nixos` (user `wiz`, host **Tawa** — Hyprland default session, Plasma 6 available, Quickshell bar, Home Manager).  
**Reference:** upstream `master` as of audit date (non-flake, `home-manager` + modular `config/programs/*` + `config/sessions/hyprland/*`).

This document lists **functional gaps** (things the reference implements that this config does not, or implements very differently) and **how** the reference wires them (packages, Nix modules, scripts, daemons).

---

## 1. High-level architecture differences

| Area | ilyamiro | This system (`wiz` / Tawa) |
|------|----------|----------------------------|
| Display manager / DE | **GDM** + **GNOME** + **Hyprland** | **SDDM** + **Plasma 6** + **Hyprland** |
| Theming | **Matugen** (wallpaper → generated colors) + **adw-gtk3** + GTK `@import` of generated CSS | **Stylix** + base16 / Hypr overrides |
| Launcher | **Rofi** (package + `config/programs/rofi`) | **Albert** (overlay from unstable) |
| Default bar / shell UI | **Multiple Quickshell instances** (`Main.qml`, `TopBar.qml`, `Floating.qml`) + **EWW** in `environment.systemPackages` | **Single Quickshell** (`quickshell/shell.qml`): workspaces, clock, audio + lock |
| Wallpaper | **swww** daemon + **mpvpaper** (video walls) in system packages | **rwpspread** (Home Manager service) |
| Screenshot | **grim** + **swappy** + **satty** + large `screenshot.sh` | **hyprshot** region → clipboard |
| Clipboard history | **cliphist** + `wl-paste` watches in Hyprland `exec-once` | Not wired the same way (no `cliphist` / dual `wl-paste` pipeline in Hyprland autostart) |

These choices cascade into which utilities make sense (e.g. matugen vs stylix, rofi vs albert).

---

## 2. Bar, monitors, and “control surface” (largest functional gap)

### Reference stack

- **Quickshell** is started **three** times from `config/sessions/hyprland/config/autostart.conf` (paths under `~/.config/hypr/scripts/quickshell/` after activation): `Main.qml`, `TopBar.qml`, `Floating.qml`.
- **`qs_manager.sh`** writes toggle state to **`/tmp/qs_widget_state`** and prepares data (e.g. wallpaper thumbnails under `~/.cache/wallpaper_picker/thumbs`, Bluetooth scan log, `nmcli` rescan for Wi‑Fi).
- **Hyprland `keybindings.conf`** binds **Super+letter** toggles to `qs_manager.sh`: `applauncher`, `clipboard`, `settings`, `music`, `battery`, `wallpaper`, `calendar`, `network`, `focustime`, `volume`, `guide`, `monitors`; workspace keys call `qs_manager.sh` with numbers (and `move` for shift).
- **Hyprland `hyprland.conf`** uses a **`passthru` submap** with a dummy **F35** bind so normal keys can fall through to Quickshell when that mode is active — a deliberate integration pattern between compositor and shell UI.

### This system

- One **Quickshell** process: `-p` → bundled `shell.qml` (workspaces 1–6, **pamixer**-driven volume icon + wheel/click, **clock**, optional audio debug; **WlSessionLock** + IPC `lock`).
- **hyprmon** is in `environment.systemPackages` for monitor layout tooling; Hyprland sources **`monitors.conf`** per host when present (`home/wayland/hyprland.nix`).
- No equivalent to **EWW**, **`qs_manager` IPC widgets**, or the **multi-QML** split (main/top/floating).

**Takeaway:** The reference is closer to a **full desktop shell** (network picker, wallpaper UI, calendar, music, battery, settings, guide, monitor mode) driven by **bash + `/tmp` IPC + Quickshell QML**. This system’s bar is intentionally **minimal**; extending toward their behavior means either growing Quickshell or adding something like **EWW** / **ags** / **Ironbar**.

---

## 3. Audio and media

| Capability | ilyamiro | This system |
|------------|----------|---------------|
| Volume / brightness OSD | **`swayosd`** + `services.swayosd` in `config/programs/swayosd/default.nix`; Hyprland binds **XF86*** to `swayosd-client` | **pamixer** + **Quickshell** overlay (`notifyChange` IPC from Hyprland binds) |
| PipeWire EQ / effects | **`services.easyeffects.enable = true`** in `home.nix`; autostart `systemctl --user enable --now easyeffects` | Not enabled in the audited `home/default.nix` imports |
| MPRIS / media keys | **`playerctl`**, **`playerctld`** in `exec-once` | No `playerctl` / `playerctld` in Hyprland config reviewed |
| Visualizer | **`cava`** in HM packages + `config/programs/cava` | Not present |
| LADSPA | **`ladspaPlugins`**, **`ladspa-sdk`** in Hypr session packages | Not in the same bundle |

**Tools to copy the idea:** `pkgs.swayosd` + `services.swayosd`, `pkgs.playerctl` + `exec-once = playerctld`, `pkgs.cava`, HM **`services.easyeffects.enable`**.

---

## 4. Weather, usage, device information

| Topic | ilyamiro | This system |
|-------|----------|-------------|
| Weather (CLI / terminal) | Not obvious in the reference repo root config; widgets may pull data inside **unfetched** Quickshell QML | **`astroterm`** in system packages; **zsh** helpers in `home/programs/zsh.nix` (`curl wttr.in/...`, `astroterm` for stars) |
| CPU / RAM / temps in bar | Likely inside **Quickshell** / **EWW** (not fully enumerated without cloning QML) | Bar does **not** show CPU/RAM/temps; **`btop`**, **`bottom`**, **`powertop`** on system |
| Sensors / power | **`lm_sensors`**, **`acpi`**, **`brightnessctl`**, **`iw`**, **`bc`** in Hyprland HM `home.packages` | **`powertop`**; brightness keys not wired to **swayosd** in Hyprland |

**Takeaway:** This system already covers **weather** and **heavy usage CLIs** well; the reference’s strength is **in-bar / overlay** device and network UX via **qs_manager + Quickshell**, not necessarily better raw CLI tools.

---

## 5. Network, Bluetooth, Wi‑Fi

| Item | ilyamiro | This system |
|------|----------|-------------|
| Wi‑Fi menu | **`networkmanager_dmenu`** in HM packages | **Albert** + Plasma stack; no `networkmanager_dmenu` |
| Quickshell “network” widget | **`qs_manager.sh toggle network`** starts **`bluetoothctl`** scan pipeline + **`nmcli` rescan** | Not present |
| `nmcli` / `networkmanager` as user packages | Yes (Hyprland bundle) | Relies on system **NetworkManager** |

---

## 6. Screenshots and recording

| Item | ilyamiro | This system |
|------|----------|-------------|
| Region / edit pipeline | **grim**, **slurp**, **swappy**, **satty**, scripted **`screenshot.sh`** | **hyprshot** |
| Screen recording | **`gpu-screen-recorder`**, **`wl-screenrec`** in system packages | Not in `common/system.nix` list |

---

## 7. System-level NixOS options (reference only)

Present in **`configuration.nix`** on the reference side, absent or different here:

- **Flatpak** — `services.flatpak.enable = true`
- **Virtualization** — `virtualisation.libvirtd`, **`virt-manager`**
- **ADB** — `programs.adb.enable`
- **Steam + GameMode** — `programs.steam`, `programs.gamemode`
- **NVIDIA + PRIME offload** — full `hardware.nvidia` / `prime` block (AMD iGPU + NVIDIA dGPU)
- **Kernel / networking tuning** — `tcp_bbr`, `fq`, large TCP buffers; **`powerManagement.cpuFreqGovernor = "performance"`**
- **Blueman** — `services.blueman.enable`
- **OpenSSH** — `services.openssh.enable`
- **Automatic nix GC** — `nix.gc` daily
- **Sudo** — `NOPASSWD` for the primary user (security tradeoff)
- **logind** — `HandlePowerKey = "ignore"` vs this system’s lid / suspend settings in `common/system.nix`

This system instead emphasizes **fwupd**, **stunnel** (VPN), **Slippi** udev/module, **nix-ld**, **AppImage**, **polkit**, fingerprint/PAM notes, etc.

---

## 8. Miscellaneous packages (reference `environment.systemPackages`)

Notable entries **not** mirrored in this system’s `common/system.nix` list (may be intentional):

- **eww**, **matugen**, **quickshell** (reference also duplicates quickshell at system level)
- **taskwarrior3**, **inotify-tools**, **pipes**, **cbonsai**, **zbar**, **yq-go**, **wmctrl**, **zenity**
- **gpu-screen-recorder**, **mpvpaper**, **gnome-tweaks**, **gnome-shell-extensions**, **papers**, **p7zip**
- **jetbrains.idea-community**, **bottles**, **qbittorrent**, **jdk8**, **steam-run**, **mingw** cross toolchain
- **telegram-desktop**, **obs-studio**, **mpv** (this system has other apps: Discord, GIMP, Godot, etc.)

---

## 9. Home Manager / program modules in the reference

Under **`config/programs/`** (each directory auto-imported from `home.nix`):

| Module | Role |
|--------|------|
| **cava** | Terminal audio visualizer config |
| **kitty** | Terminal |
| **matugen** | Symlink `~/.config/matugen` → `/etc/nixos/config/programs/matugen` |
| **neovim** | Editor |
| **plymouth** | Theme assets (referenced from `configuration.nix` boot theme) |
| **rofi** | Launcher theme/config |
| **swayosd** | OSD service + `style.css` |
| **zsh** | Shell |

**`home.nix`** also sets **GTK/Qt** theming, **cursor** from **fetchzip** (ArcMidnight), **fonts** from `./config/fonts`, and **`xdg.portal`**.

---

## 10. What this system already does well (vs the reference)

- **Declarative Home Manager** layout (`home/default.nix`, Stylix, Firefox, Kitty, Hypridle, Spotifyd, XDG, etc.)
- **Quickshell lock** integrated with Hyprland and idle (`quickshell-lock`, PAM)
- **Hyprland + Plasma** coexistence and **portal** defaults (`hyprland`, `gtk`, `kde`)
- **Weather / sky** via **astroterm** + **wttr** zsh aliases
- **Monitor file** per host + **hyprmon**
- **Screenshot** simplicity with **hyprshot**

---

## 11. Practical “import list” if you want reference-like behavior

Ordered roughly by impact:

1. **`playerctl` + `playerctld`** — media keys and widget data.  
2. **`swayosd`** + Hyprland binds for brightness/caps/volume — complements or replaces parts of the custom Quickshell OSD.  
3. **`cliphist`** + **`wl-clipboard`** `exec-once` watches — clipboard history.  
4. **`services.easyeffects.enable`** — system-wide EQ / effects.  
5. **`swww`** or keep **rwpspread** but add **mpvpaper** if you want video wallpapers.  
6. **Matugen** *or* stay on Stylix — usually pick one primary color pipeline.  
7. **EWW** or expand **Quickshell** for CPU/RAM/net/battery widgets (reference: **qs_manager** pattern).  
8. **`networkmanager_dmenu`** or a Quickshell network panel.  
9. **`cava`** for ricing / audio feedback.  
10. **grim/swappy/satty** if you want an annotation-heavy screenshot flow.

---

## 12. How to verify upstream details

The reference layout is:

- [`configuration.nix`](https://github.com/ilyamiro/nixos-configuration/blob/master/configuration.nix) — system packages, GNOME/GDM/Hyprland, NVIDIA, Steam, etc.  
- [`home.nix`](https://github.com/ilyamiro/nixos-configuration/blob/master/home.nix) — dynamic imports, GTK/matugen, easyeffects.  
- [`config/sessions/hyprland/`](https://github.com/ilyamiro/nixos-configuration/tree/master/config/sessions/hyprland) — `default.nix`, `hyprland.conf`, `config/*.conf`, **`scripts/`** (`qs_manager.sh`, `screenshot.sh`, `volume_listener.sh`, `settings_watcher.sh`, **`quickshell/`** QML tree).  
- [`config/programs/`](https://github.com/ilyamiro/nixos-configuration/tree/master/config/programs) — per-app HM modules.

Upstream **README** states the config still needs adaptation and is not a drop-in flake; treat it as **patterns and package lists**, not something to merge blindly.

---

*Generated for local planning; re-fetch upstream if you need exact parity with a specific commit.*

# Analysis: current Surface config vs flake repo

Snapshot date: 2026-08-21. Current system: standalone `/home/wiz/.config/nixos`
(non-flake, channel-based). Target: https://github.com/ngrayson/nixos (flake).

## Side-by-side

| Area | Current Surface (standalone) | Flake repo (Tawa/Theseus/Gcp) | Plan for Hearth |
|------|------------------------------|-------------------------------|-----------------|
| Nix release | 24.05 channels (`system.stateVersion = "24.05"`) | nixpkgs / home-manager / stylix pinned to **26.05**, unstable overlay available | Build from 26.05 pins; keep `stateVersion = "24.05"` (never bump) |
| Structure | Single `configuration.nix` + generated `hardware-configuration.nix` | `flake.nix` -> `hosts/<Name>/{configuration,host,hardware-configuration}.nix` + `common/` + `profiles/` + `home/` | New `hosts/Hearth/` following NEW-SYSTEM.md |
| Surface hardware | `<nixos-hardware/microsoft/surface/common>` channel-style import inside `hardware-configuration.nix`; `hardware.microsoft-surface.kernelVersion = "stable"` | nixos-hardware is a flake input; hardware modules go in the host's module list in `flake.nix` | `nixos-hardware.nixosModules.microsoft-surface-common` in `flake.nix`; keep `kernelVersion = "stable"` in `host.nix`; strip the channel import from the preserved hardware file |
| Desktop | Plasma 6 + SDDM only | Plasma 6 **and** Hyprland, default session `hyprland`, SDDM breeze-login theme, Plymouth splash | Hyprland + SDDM only (skip Plasma to stay light); reuse SDDM breeze-login look |
| Home-manager | none | Full HM for `wiz` (`home.nix` -> `home/default.nix`): Hyprland rice, quickshell, Stylix, kitty, dunst, hypridle, spotifyd, albert, slippi | New slim HM entry (`home/media.nix`) with only session/theme/hyprland/kitty/zsh/git/dunst essentials |
| Theming | Breeze Dark + accent RGB(180,101,90); Konsole "Ghost Color Scheme"; BeautyLine icons; wallpaper `~/Documents/Tomes/_assets/telePole.jpg` | Stylix + repo theme system: `home/theme/hosts.nix` maps host -> scheme (`izar`, `lilac-ash`) + wallpaper | New `home/theme/schemes/ghost.nix` ported from the Konsole scheme; `telePole.jpg` copied into repo; Hearth entry in `hosts.nix` (additive) |
| Terminal | Konsole + oh-my-zsh "jonathan", Iosevka Nerd Font | kitty (theme-managed) + zsh via HM, fastfetch with host-scoped extras | kitty with ghost palette; fastfetch works out of the box; optional `fastfetch/Hearth/` extras |
| Touchpad | `services.libinput.enable` only; palm rejection while typing NOT working under Plasma | Same single line in `common/system.nix`; no touchpad tuning anywhere | Phase 4: Hyprland `input:touchpad` dwt + libinput quirks if needed |
| Media | none | Jellyfin on Tawa only (`hosts/Tawa/jellyfin.nix`, `/srv/media`, firewall open) | Same pattern for Hearth + Intel VAAPI transcoding + lid-closed server policy |
| VPN | openvpn `zurich` server (config file at `/root/etc/openvpn/zurich.ovpn`) | Vortix/stunnel FrootVPN stack in `common/vpn-vortix.nix` (workstations only) | Omit on Hearth (lightweight); old zurich openvpn dropped unless requested |
| Packages (heavy) | Steam, Discord, Obsidian, LibreOffice, VS Code, node, gcc/gnumake, appimage-run/slippi deps | Even bigger workstation set in `common/system.nix` | None of these on Hearth; CLI basics + kitty + firefox + jellyfin only |
| Swap/zram | 16 GiB swapfile (hardware file) + zram 25% | per-host | Keep both, moved to `hosts/Hearth/` |
| Locale/TZ | `America/Los_Angeles`, `en_US.UTF-8` | `common/base.nix`: `America/Vancouver`, `en_CA.UTF-8` | Accept base.nix (same Pacific timezone); no override |
| Shell | zsh + oh-my-zsh (jonathan theme, git/npm/fzf plugins) | zsh via HM `home/programs/zsh.nix` | Use repo zsh config (parity with other hosts) |
| Rebuild tooling | local `wizos-rebuild` script | `os-rebuild` helper (documented in NEW-SYSTEM.md) | Use `os-rebuild --host Hearth`; retire `wizos-rebuild` |

## Key facts pinned down during analysis

### Ghost palette (from `~/.local/share/konsole/Ghost Color Scheme.colorscheme`)

Normal / Intense (hex):

| Slot | Normal | Intense |
|------|--------|---------|
| Background | `#122221` | `#00474D` (faint `#182D2B`) |
| Foreground | `#ACDCDD` | `#C5FBFC` (faint `#96C8C9`) |
| 0 black | `#203D3B` | `#20F3E5` |
| 1 red | `#B15A65` | `#EC446C` |
| 2 green | `#3F947D` | `#39E2B2` |
| 3 yellow | `#C46F5A` | `#FD8D74` |
| 4 blue | `#3C6784` | `#70C1F7` |
| 5 magenta | `#A081B6` | `#E0B5FF` |
| 6 cyan | `#2FC7BE` | `#3CFDF0` |
| 7 white | `#B2B2B2` | `#FFFFFF` |

KDE accent color today: RGB(180,101,90) = `#B4655A` (terracotta, close to the
Ghost yellow slot `#C46F5A`). Konsole font: Iosevka Nerd Font Mono 12.

### Wallpaper

`/home/wiz/Documents/Tomes/_assets/telePole.jpg` (898 KiB JPEG). Must be copied
into the repo (theme wallpapers are repo-relative paths, cf. `izar-utopia.png`).

### Hardware file to preserve (`hardware-configuration.nix`)

- root ext4 UUID `6d7ec514-c117-413b-b714-4483afed39f4`, boot vfat `5E44-2C1A`
- 16 GiB swapfile `/var/lib/swapfile`
- `kvm-intel`, initrd modules `xhci_pci nvme usb_storage sd_mod`
- Contains a channel-style `<nixos-hardware/microsoft/surface/common>` import
  that must be REMOVED (replaced by the flake-input module in `flake.nix`)

### Flake repo facts that shape the plan

- `mkHost` injects home-manager NixOS module for every host, but HM users are
  only declared inside `common/system.nix` — so a host that skips `system.nix`
  has no HM unless its profile declares it.
- `home/theme/default.nix` **throws** if the hostname is missing from
  `home/theme/hosts.nix` — Hearth must be added there before HM activates.
- `common/system.nix` is the de-facto "workstation profile" (Plasma+Hyprland+
  Steam+Slippi+VPN+~60 GUI packages). Importing it wholesale contradicts the
  lightweight goal; only `profiles/server.nix` (headless) exists as an
  alternative. A new slim profile is required (phase 2).
- Jellyfin exists as a host-local module on Tawa; NixOS 25.11+ has no
  `services.jellyfin.hardwareAcceleration` — VAAPI is enabled in the web UI.
- The flake is git-backed: **untracked files are invisible to builds**; every
  new file must be `git add`ed before rebuilding.
- `home/session.nix` sets shared `home.stateVersion = "25.11"`; the slim home
  entry must set its own value if it does not import `session.nix`.

## Risks

1. **Surface kernel build time**: `microsoft-surface-common` builds a patched
   linux-surface kernel from source; there is no public binary cache for it.
   On the Surface itself this can take hours. Mitigations: build the toplevel
   on Tawa/Theseus and `nix copy` to the Surface, or temporarily run the stock
   kernel (comment the nixos-hardware module) and verify touch/palm behaviour
   before committing to the patched kernel.
2. **24.05 -> 26.05 jump**: two-year channel jump on one switch. stateVersion
   stays 24.05 so stateful services keep old formats; main risk is user-visible
   app churn, acceptable on a machine being repurposed anyway.
3. **Shared-file edits**: theme `hosts.nix` and `flake.nix` must be touched
   (additive). Any deeper refactor of `common/system.nix` is explicitly out of
   scope; Hearth's profile duplicates the few GUI settings it needs instead.
4. **Hyprland home modules coupled to workstation features**: e.g.
   `home/hypr/scripts.nix` has Slippi guards, quickshell may reference
   spotifyd. The slim HM set must be audited so nothing references missing
   services; prefer omitting a module over editing a shared one.

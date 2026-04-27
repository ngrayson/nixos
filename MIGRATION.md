# Migrating this NixOS config to a new machine (e.g. new Framework)

This repo is the source of truth for system configuration. Use this list when reinstalling on new hardware.

## Before you leave the old machine

1. **Push this repo** to your remote: `git push` (private remote recommended if PEMs or sensitive paths are in-tree).
2. **Confirm** `login-bg.png` is a **regular file** in the repo (not a symlink to `~/Pictures/…`), so the flake/path works on a fresh clone.
3. **Back up** anything **not** in Git: GPG/SSH private keys, browser profiles you care about, any `~/.config` you still manage only on disk, and any ad-hoc `nix profile` or Flatpak you want to recreate.

## Fresh install (high level)

1. Boot the **NixOS installer** ISO.
2. Partition, encrypt (LUKS) if you use it, format, mount. Run **`nixos-generate-config --root /mnt`**.
3. Clone this repository (or copy in `configuration.nix` and assets) under `/mnt/etc/nixos` or your chosen `NIXOS_CONFIG` location.
4. **Do not** blindly reuse the old **`hardware-configuration.nix`**. On a new host, create **`hosts/<hostname>/`**, copy the installer’s `hardware-configuration.nix` there, add **`host.nix`** (`networking.hostName`, nixos-hardware, LUKS, `kernelParams`), and **`configuration.nix`** that imports `../../common/system.nix`, `./hardware-configuration.nix`, and `./host.nix`. Then set **`NIXOS_CONFIG`** to **`…/hosts/<hostname>/configuration.nix`** (or change the root [`configuration.nix`](./configuration.nix) import if this machine is the default in git). Start from the **new** `nixos-generate-config` output, then **merge** intentional settings from the previous machine:
   - `fileSystems` and **`boot.initrd.luks.devices`** (names and **UUIDs will change** with new disks/partitions)
   - `boot.initrd.availableKernelModules` / `kernelModules` as needed
   - `swapDevices` if applicable
5. This repo includes **Home Manager** (entry [`home.nix`](./home.nix) imports the modular **[`./home/`](./home/)** tree; HM is pinned in [`common/system.nix`](./common/system.nix) via `fetchTarball` on the `release-25.11` branch). It activates with **`sudo nixos-rebuild switch`** the same as the rest of the system. On a fresh clone, no extra `home-manager` install step is required. **User session env** lives in [`home/session.nix`](./home/session.nix) (`home.sessionVariables`; see log below). **Dotfiles for user `wiz` are Home Manager only** — this repo does not use chezmoi.
6. **Shared** system options live in **[`common/system.nix`](./common/system.nix)**. Per-machine options live under **`hosts/<hostname>/`** (see **`host.nix`** for **`networking.hostName`**, **`<nixos-hardware/...>`**, **LUKS**, **`boot.kernelParams`**).
7. Set **`system.stateVersion`** to match your *first* NixOS install on the new box if the installer suggests a new default; do not advance casually (see NixOS manual).
8. Run **`sudo nixos-rebuild switch`** (or the flake equivalent) and reboot. That also runs **Home Manager** for user `wiz` (systemd `home-manager-wiz.service` or equivalent on your NixOS version).
9. Install Cursor + Cursor CLI in a way that matches this repo: see [`CURSOR_SETUP.md`](./CURSOR_SETUP.md).

## After first successful boot

1. **Fingerprint**: Re-enroll in Plasma settings (`fprintd`); hardware is a new device.
2. **WiFi**: Reconnect via NetworkManager (or add declarative connection files later).
3. **KWallet / wallet prompt**: If something prompts unexpectedly, it is often the same PAM/fingerprint/KWallet story as in the NixOS wiki; log in with **password** first, then align fingerprint in **Settings** if needed.
4. **VPN / stunnel**: Ensure **`/etc/...` paths** from `configuration.nix` (e.g. FrootVPN CA) exist; PEM is referenced from this repo in **`environment.etc`**, so a successful rebuild already places it.
5. **Dotfiles:** Anything you still need from an old **chezmoi** setup should be merged into the appropriate file under **[`./home/`](./home/)** (e.g. [`home/xdg/config.nix`](./home/xdg/config.nix), [`home/programs/zsh.nix`](./home/programs/zsh.nix)), then remove chezmoi’s copy under **`~/.local/share/chezmoi`** on the machine if you are done with it.
6. **Plymouth / SDDM**: After rebuild, log out to SDDM once to confirm **theme** and **login background** (`breeze-login`, `login-bg.png`).

## Optional: Framework setup roadmap (documentation)

A **vendored copy** of the Stellarium **NixOS on Framework** project may live in **`documentation/nixos-framework-setup/`** in this repository (full files, not symlinks, so clones stay portable). It is the **phased checklist** (LOCKED, audit, session, Home Manager, rice) — **documentation only**; it does not change `nixos-rebuild` by itself. If you also keep a copy under a Stellarium checkout (`projects/nixos-framework-setup/`, gitignored at the Stellarium root), **sync the trees manually** when you want them to match.

**Home Manager layout:** Root [`home.nix`](./home.nix) is only `imports = [ ./home ];`. **[`home/default.nix`](./home/default.nix)** pulls in modules such as [`home/session.nix`](./home/session.nix), [`home/programs/`](./home/programs/), [`home/wayland/hyprland.nix`](./home/wayland/hyprland.nix), [`home/services/hypridle.nix`](./home/services/hypridle.nix), [`home/xdg/`](./home/xdg/), [`home/hypr/scripts.nix`](./home/hypr/scripts.nix), and [`home/lib/`](./home/lib/). Remaining roadmap work (optional rice, extra `xdg.*`) follows `documentation/nixos-framework-setup/06-implementation-checklist.md` and `LOCKED.md` there (those docs include a 2026-04-05 Framework snapshot; this repo’s live layout is described here and in the migration log).

### Home Manager path ownership (audit, Tawa / `~/.config/nixos`)

Use **one owner per path** — Home Manager for user config tracked in this repo. If you used chezmoi before, do not run **`chezmoi apply`** against this home without removing or renaming that tree, or it can overwrite HM-managed files.

| Path or topic | Current owner (typical) | Next HM / Nix step |
|---------------|-------------------------|--------------------|
| Session env (`EDITOR`, `TERMINAL`, …) | [`home/session.nix`](./home/session.nix) (imported from [`home.nix`](./home.nix)) | Done (step 1; `GIT_CONFIG_SYSTEM` removed in step 4) |
| `fastfetch` CLI | `home.packages` in [`home/session.nix`](./home/session.nix) | Done (step 2 — proof) |
| User git config (`~/.config/git/config`) | [`home/programs/git.nix`](./home/programs/git.nix) | **Done (step 4).** NixOS `programs.git` removed from `configuration.nix`. |
| `~/.zshrc` (HM-generated) + zsh | [`home/programs/zsh.nix`](./home/programs/zsh.nix) | **Done (step 5).** `zshconfig` / `ohmyzshconfig` → `micro ~/.config/nixos/home/default.nix`. |
| `~/.config/kitty/kitty.conf` + `lilac-ash.conf` | HM `xdg.configFile` in [`home/xdg/config.nix`](./home/xdg/config.nix) from [`kitty/`](./kitty/) in this repo; **`kitty` package in `environment.systemPackages`** (Plasma shortcuts need system `PATH`) | **Done (step 3).** |
| `~/.config/fastfetch/config.jsonc` + logo | HM `xdg.configFile` in [`home/xdg/config.nix`](./home/xdg/config.nix) from [`fastfetch/`](./fastfetch/) in this repo | **Done (step 6).** Theme logo path `~/.config/fastfetch/izar-tsp.gif`; you can remove stale `~/.config/izar-tsp.gif` after verify. |
| `~/.config/obsidian` / `Cursor` / browser profiles | App defaults | Often stay imperative or app-managed |
| `chezmoi` tool | *removed* | No longer in `environment.systemPackages`; use HM only. |
| `tmux`, `tmuxifier`, `newsboat` | `home.packages` in [`home/session.nix`](./home/session.nix) | **Done (step 6).** Removed from `environment.systemPackages`. |
| `~/.config/newsboat` (URLs) | Runtime / user | Still imperative unless you add `xdg` or HM later. |
| `~/.local/share/applications/*.desktop` (custom) | [`desktop/applications/`](./desktop/applications/) → HM **`xdg.dataFile`** via [`home/xdg/data.nix`](./home/xdg/data.nix) + [`home/lib/desktop-data.nix`](./home/lib/desktop-data.nix) | Drop `*.desktop` in that dir; see [`README`](./desktop/applications/README.md). |
| `~/.config/Kvantum/` (Qt style) | [`kvantum/<hostname>/`](./kvantum/README.md) → HM **`xdg.configFile`** ([`home/lib/host-xdg.nix`](./home/lib/host-xdg.nix) + [`home/xdg/config.nix`](./home/xdg/config.nix)) | Per-host dir named like `networking.hostName`; see [`kvantum/README.md`](./kvantum/README.md). |

### Home Manager migration log

Iterative: **one** logical change per rebuild; **verify** before the next (see `documentation/nixos-framework-setup/` roadmap).

- **2026-04-17 — Step 1 (session env):** `home.sessionVariables` holds `EDITOR`, `SYSTEMD_EDITOR`, `VISUAL`, `TERMINAL` in **[`home/session.nix`](./home/session.nix)** (previously also `GIT_CONFIG_SYSTEM` pointing at `/etc/gitconfig`; superseded in **step 4**). Rebuild: `sudo nixos-rebuild switch`. **Verify:** new Kitty/Konsole: `echo "$EDITOR" "$TERMINAL"`.
- **2026-04-17 — Step 2 (proof package):** `fastfetch` moved from `environment.systemPackages` to `home.packages` in **[`home/session.nix`](./home/session.nix)** (user `wiz` only). Rebuild: `sudo nixos-rebuild switch`. **Verify:** `command -v fastfetch` and `fastfetch` in a new login shell; `fetch` zsh alias still works.
- **2026-04-17 — Step 3 (Kitty):** Config from [`./kitty/kitty.conf`](./kitty/kitty.conf) + [`./kitty/lilac-ash.conf`](./kitty/lilac-ash.conf) via `xdg.configFile` in **[`home/xdg/config.nix`](./home/xdg/config.nix)** (not `programs.kitty` — avoids a second generated `kitty.conf`). **`kitty` is in `environment.systemPackages`** so Plasma keyboard shortcuts see it on the system `PATH` (user-only `home.packages` was not enough for Alt+Enter–style launchers). `termconfig` alias edits the **nixos repo** `kitty/` files. Rebuild: `sudo nixos-rebuild switch`. **Verify:** new Kitty. If the first `switch` failed with *would be clobbered*, those `xdg` entries use `force = true` to replace existing files (back up first if you need the old `kitty.conf`).
- **2026-04-17 — Step 4 (Git):** `programs.git` moved from NixOS `configuration.nix` to **[`home/programs/git.nix`](./home/programs/git.nix)** (`settings` → `~/.config/git/config` per Home Manager). Removed `GIT_CONFIG_SYSTEM` from `home.sessionVariables`. Rebuild: `sudo nixos-rebuild switch`. **Verify:** `git config --list --show-origin` shows the expected entries from `~/.config/git/config`; `git` from a user shell still has GitHub / gist credential helpers; **`sudo` / minimal PATH:** if you need `git` as root without logging in as `wiz`, add `git` to `environment.systemPackages` (optional; HM installs `git` for user `wiz` only).
- **2026-04-18 — Step 5 (zsh):** Interactive `programs.zsh` (Oh My Zsh, autosuggestion, syntax highlighting, `zsh-autoenv` via `initContent` order 1500, shell aliases) lives in **[`home/programs/zsh.nix`](./home/programs/zsh.nix)**. **`programs.zsh.enable = true`** remains in [`common/system.nix`](./common/system.nix) with **no** extra NixOS zsh options — required so login shells (including `root` if it uses zsh) get the usual NixOS `/etc` zsh `PATH` setup. `users.users.wiz.shell` / `defaultUserShell` stay **`pkgs.zsh`**. Rebuild: `sudo nixos-rebuild switch`. **Verify:** new login or `exec zsh -l` — same theme/aliases; `grep -E 'oh-my|autoenv' ~/.zshrc` shows managed bits. **If activation fails** with *Existing file* would be clobbered* for `~/.zshrc` / `~/.zshenv`:** do **not** set `home.file."…".force` (conflicts with `programs.zsh`); set **`home-manager.backupFileExtension = "hm-backup"`** in [`common/system.nix`](./common/system.nix) (first `switch` renames the old file to e.g. `.zshrc.hm-backup`), then remove the backups when satisfied.
- **2026-04-26 — Chezmoi removed:** `chezmoi` dropped from `environment.systemPackages`; shell alias `config` opens **`~/.config/nixos`** in Cursor; **`chezpush`** alias removed. Do not run **`chezmoi apply`** on this machine unless you still maintain a separate chezmoi tree and know it will not overwrite HM files.
- **2026-04-26 — Step 6 (fastfetch + user CLIs):** [`./fastfetch/config.jsonc`](./fastfetch/config.jsonc) + [`./fastfetch/izar-tsp.gif`](./fastfetch/izar-tsp.gif) vendored; `xdg.configFile` in **[`home/xdg/config.nix`](./home/xdg/config.nix)**. **`tmux`**, **`tmuxifier`**, **`newsboat`** moved from `environment.systemPackages` to `home.packages` in **[`home/session.nix`](./home/session.nix)** (with **`fastfetch`**). Rebuild: `sudo nixos-rebuild switch`. **Verify:** `command -v tmux fastfetch newsboat`, **`fastfetch`** shows logo; remove obsolete **`~/.config/izar-tsp.gif`** if present.
- **2026-04-26 — `hosts/Theseus/` (Framework laptop):** Entrypoint mirrors **Tawa**; **`hardware-configuration.nix`** is a **stub** (placeholder UUIDs) so `nix build -I nixos-config=…/hosts/Theseus/configuration.nix` evaluates from any machine. On the laptop, replace that file with **`nixos-generate-config`** output before **`nixos-rebuild switch`**. **`kvantum/Theseus/`** copies the Tawa theme layout until you customize on-device.
- **2026-04-27 — `hostname.nix`:** (superseded) Previously per-host settings lived in `./hostname.nix`.
- **2026-04-27 — `hosts/<hostname>/`:** Per-host **`networking.hostName`**, **`<nixos-hardware/...>`**, **LUKS**, **`boot.kernelParams`** live in **`hosts/<hostname>/host.nix`**; disk layout in **`hosts/<hostname>/hardware-configuration.nix`**; entry **`hosts/<hostname>/configuration.nix`**. Shared NixOS + HM pin in **[`common/system.nix`](./common/system.nix)**. Root [`configuration.nix`](./configuration.nix) imports **`./hosts/Tawa/configuration.nix`** for this desktop; other machines set **`NIXOS_CONFIG`** to their host entry (or change the root import on a branch).
- **2026-04-28 — Custom `.desktop` files:** Each `*.desktop` in [`./desktop/applications/`](./desktop/applications/) is installed to **`~/.local/share/applications/`** via **`xdg.dataFile`** in **[`home/xdg/data.nix`](./home/xdg/data.nix)** ([`home/lib/desktop-data.nix`](./home/lib/desktop-data.nix); no need to list files in Nix; `readDir` picks them up). Rebuild: `sudo nixos-rebuild switch`.
- **2026-04-29 — Kvantum (per host):** Theme + `kvantum.kvconfig` from [`./kvantum/<hostname>/`](./kvantum/README.md) (hostname = **`networking.hostName`**, e.g. **Tawa**) via **`nixosConfig.networking.hostName`** in **[`home/lib/host-xdg.nix`](./home/lib/host-xdg.nix)** (merged in **[`home/xdg/config.nix`](./home/xdg/config.nix)**). Rebuild: `sudo nixos-rebuild switch`. Add new `xdg.configFile` paths in **`host-xdg.nix` / `config.nix`** if a host’s theme adds files not wired there yet.
- **2026-04-26 — Modular Home Manager:** User config is split under **[`./home/`](./home/)** (e.g. `programs/`, `wayland/`, `xdg/`); root **[`home.nix`](./home.nix)** only re-exports `imports = [ ./home ];`. **`hyprctl` from hypridle** often has no `HYPRLAND_INSTANCE_SIGNATURE`; helper scripts use **`hyprctl -i 0`** so `dispatch dpms` works. Rebuild: `sudo nixos-rebuild switch`.

## Optional: per-machine Nix

A **gitignored** `local.nix` is still an option for secrets you do not want in git. Host identity and disk UUIDs belong under **`hosts/<hostname>/`** (`host.nix` / `hardware-configuration.nix`).

## Flakes (optional)

If you move to a **flake** + **`flake.lock`**, record that in a short “build command” note here (e.g. `nixos-rebuild switch --flake .#hostname`).

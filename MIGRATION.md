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
4. **Do not** blindly reuse the old **`hardware-configuration.nix`**. Start from the **new** `nixos-generate-config` output, then **merge** intentional settings from the previous machine:
   - `fileSystems` and **`boot.initrd.luks.devices`** (names and **UUIDs will change** with new disks/partitions)
   - `boot.initrd.availableKernelModules` / `kernelModules` as needed
   - `swapDevices` if applicable
5. This repo includes **Home Manager** (`./home.nix`, pinned in `configuration.nix` via `fetchTarball` on the `release-25.11` branch). It activates with **`sudo nixos-rebuild switch`** the same as the rest of the system. On a fresh clone, no extra `home-manager` install step is required. **User session env** may live in [`home.nix` via `home.sessionVariables`](./MIGRATION.md#home-manager-migration-log) (see log below). **Dotfiles for user `wiz` are Home Manager only** — this repo does not use chezmoi.
6. In **`configuration.nix`**, update at least:
   - **`networking.hostName`** (e.g. old `Theseus` → new name)
   - **`<nixos-hardware/...>`** import when a profile exists for the **new** Framework model (path may differ from `framework/13-inch/amd-ai-300-series`); if none exists yet, comment the import and add hardware options manually.
   - **Kernel / boot**: Re-evaluate **`linuxPackages_latest`** and **`boot.kernelParams`** (e.g. `amd_pstate=active`) if the CPU is no longer the same (Intel vs AMD, etc.).
7. Set **`system.stateVersion`** to match your *first* NixOS install on the new box if the installer suggests a new default; do not advance casually (see NixOS manual).
8. Run **`sudo nixos-rebuild switch`** (or the flake equivalent) and reboot. That also runs **Home Manager** for user `wiz` (systemd `home-manager-wiz.service` or equivalent on your NixOS version).
9. Install Cursor + Cursor CLI in a way that matches this repo: see [`CURSOR_SETUP.md`](./CURSOR_SETUP.md).

## After first successful boot

1. **Fingerprint**: Re-enroll in Plasma settings (`fprintd`); hardware is a new device.
2. **WiFi**: Reconnect via NetworkManager (or add declarative connection files later).
3. **KWallet / wallet prompt**: If something prompts unexpectedly, it is often the same PAM/fingerprint/KWallet story as in the NixOS wiki; log in with **password** first, then align fingerprint in **Settings** if needed.
4. **VPN / stunnel**: Ensure **`/etc/...` paths** from `configuration.nix` (e.g. FrootVPN CA) exist; PEM is referenced from this repo in **`environment.etc`**, so a successful rebuild already places it.
5. **Dotfiles:** Anything you still need from an old **chezmoi** setup should be copied into **`./home.nix`** (or `xdg.configFile` / `programs.*` there), then remove chezmoi’s copy under **`~/.local/share/chezmoi`** on the machine if you are done with it.
6. **Plymouth / SDDM**: After rebuild, log out to SDDM once to confirm **theme** and **login background** (`breeze-login`, `login-bg.png`).

## Optional: Framework setup roadmap (documentation)

A **vendored copy** of the Stellarium **NixOS on Framework** project may live in **`documentation/nixos-framework-setup/`** in this repository (full files, not symlinks, so clones stay portable). It is the **phased checklist** (LOCKED, audit, session, Home Manager, rice) — **documentation only**; it does not change `nixos-rebuild` by itself. If you also keep a copy under a Stellarium checkout (`projects/nixos-framework-setup/`, gitignored at the Stellarium root), **sync the trees manually** when you want them to match.

**Home Manager note:** `home.nix` in this repo now holds **session env, kitty, git, zsh**, and more (see the migration log). Remaining roadmap work (optional rice, extra `xdg.*`) follows `documentation/nixos-framework-setup/06-implementation-checklist.md` and `LOCKED.md` there (those docs still mention chezmoi historically; this repo no longer uses it).

### Home Manager path ownership (audit, Theseus / `~/.config/nixos`)

Use **one owner per path** — Home Manager for user config tracked in this repo. If you used chezmoi before, do not run **`chezmoi apply`** against this home without removing or renaming that tree, or it can overwrite HM-managed files.

| Path or topic | Current owner (typical) | Next HM / Nix step |
|---------------|-------------------------|--------------------|
| Session env (`EDITOR`, `TERMINAL`, …) | [`home.nix`](./home.nix) `home.sessionVariables` | Done (step 1; `GIT_CONFIG_SYSTEM` removed in step 4) |
| `fastfetch` CLI | `home.packages` in [`home.nix`](./home.nix) | Done (step 2 — proof) |
| User git config (`~/.config/git/config`) | [`programs.git`](./home.nix) in [`home.nix`](./home.nix) | **Done (step 4).** NixOS `programs.git` removed from `configuration.nix`. |
| `~/.zshrc` (HM-generated) + zsh | [`programs.zsh`](./home.nix) in [`home.nix`](./home.nix) | **Done (step 5).** `zshconfig` / `ohmyzshconfig` → `micro ~/.config/nixos/home.nix`. |
| `~/.config/kitty/kitty.conf` + `lilac-ash.conf` | HM `xdg.configFile` from [`kitty/`](./kitty/) in this repo; **`kitty` package in `environment.systemPackages`** (Plasma shortcuts need system `PATH`) | **Done (step 3).** |
| `~/.config/fastfetch/config.jsonc` | User-edited, not in Nix | `xdg.configFile` or `programs.fastfetch` in HM later (optional) |
| `~/.config/obsidian` / `Cursor` / browser profiles | App defaults | Often stay imperative or app-managed |
| `chezmoi` tool | *removed* | No longer in `environment.systemPackages`; use HM only. |
| `~/.config/newsboat`, `tmux`, etc. | Mixed | `programs.*` or `xdg` in HM in separate steps |

### Home Manager migration log

Iterative: **one** logical change per rebuild; **verify** before the next (see `documentation/nixos-framework-setup/` roadmap).

- **2026-04-17 — Step 1 (session env):** `home.sessionVariables` in `./home.nix` holds `EDITOR`, `SYSTEMD_EDITOR`, `VISUAL`, `TERMINAL` (previously also `GIT_CONFIG_SYSTEM` pointing at `/etc/gitconfig`; superseded in **step 4**). Rebuild: `sudo nixos-rebuild switch`. **Verify:** new Kitty/Konsole: `echo "$EDITOR" "$TERMINAL"`.
- **2026-04-17 — Step 2 (proof package):** `fastfetch` moved from `environment.systemPackages` to `home.packages` in `./home.nix` (user `wiz` only). Rebuild: `sudo nixos-rebuild switch`. **Verify:** `command -v fastfetch` and `fastfetch` in a new login shell; `fetch` zsh alias still works.
- **2026-04-17 — Step 3 (Kitty):** Config from [`./kitty/kitty.conf`](./kitty/kitty.conf) + [`./kitty/lilac-ash.conf`](./kitty/lilac-ash.conf) via `xdg.configFile` in `./home.nix` (not `programs.kitty` — avoids a second generated `kitty.conf`). **`kitty` is in `environment.systemPackages`** so Plasma keyboard shortcuts see it on the system `PATH` (user-only `home.packages` was not enough for Alt+Enter–style launchers). `termconfig` alias edits the **nixos repo** `kitty/` files. Rebuild: `sudo nixos-rebuild switch`. **Verify:** new Kitty. If the first `switch` failed with *would be clobbered*, `home.nix` uses `force = true` on those `xdg` entries to replace existing files (back up first if you need the old `kitty.conf`).
- **2026-04-17 — Step 4 (Git):** `programs.git` moved from NixOS `configuration.nix` to [`programs.git`](./home.nix) in `./home.nix` (`settings` → `~/.config/git/config` per Home Manager). Removed `GIT_CONFIG_SYSTEM` from `home.sessionVariables`. Rebuild: `sudo nixos-rebuild switch`. **Verify:** `git config --list --show-origin` shows the expected entries from `~/.config/git/config`; `git` from a user shell still has GitHub / gist credential helpers; **`sudo` / minimal PATH:** if you need `git` as root without logging in as `wiz`, add `git` to `environment.systemPackages` (optional; HM installs `git` for user `wiz` only).
- **2026-04-18 — Step 5 (zsh):** Interactive `programs.zsh` (Oh My Zsh, autosuggestion, syntax highlighting, `zsh-autoenv` via `initContent` order 1500, shell aliases) lives in [`programs.zsh`](./home.nix) in `./home.nix`. **`programs.zsh.enable = true`** remains in `configuration.nix` with **no** extra NixOS zsh options — required so login shells (including `root` if it uses zsh) get the usual NixOS `/etc` zsh `PATH` setup. `users.users.wiz.shell` / `defaultUserShell` stay **`pkgs.zsh`**. Rebuild: `sudo nixos-rebuild switch`. **Verify:** new login or `exec zsh -l` — same theme/aliases; `grep -E 'oh-my|autoenv' ~/.zshrc` shows managed bits. **If activation fails** with *Existing file* would be clobbered* for `~/.zshrc` / `~/.zshenv`:** do **not** set `home.file."…".force` (conflicts with `programs.zsh`); set **`home-manager.backupFileExtension = "hm-backup"`** in `configuration.nix` (first `switch` renames the old file to e.g. `.zshrc.hm-backup`), then remove the backups when satisfied.
- **2026-04-26 — Chezmoi removed:** `chezmoi` dropped from `environment.systemPackages`; shell alias `config` opens **`~/.config/nixos`** in Cursor; **`chezpush`** alias removed. Do not run **`chezmoi apply`** on this machine unless you still maintain a separate chezmoi tree and know it will not overwrite HM files.

## Optional: split machine-specific Nix

For less editing next time, you can add a small **`machine.nix`** (or gitignored `local.nix`) imported from `configuration.nix` that only sets **`hostName`**, **LUKS device entries**, and **nixos-hardware** import, keeping the main file shared across machines.

## Flakes (optional)

If you move to a **flake** + **`flake.lock`**, record that in a short “build command” note here (e.g. `nixos-rebuild switch --flake .#hostname`).

# Migrating this NixOS config to a new machine (e.g. new Framework)

This repo is the source of truth for system configuration. Use this list when reinstalling on new hardware.

## Before you leave the old machine

1. **Push this repo** to your remote: `git push` (private remote recommended if PEMs or sensitive paths are in-tree).
2. **Confirm** `login-bg.png` is a **regular file** in the repo (not a symlink to `~/Pictures/…`), so the flake/path works on a fresh clone.
3. **Back up** anything **not** in Git: GPG/SSH private keys, browser profiles you care about, `~/.config` not managed by chezmoi, and any ad-hoc `nix profile` or Flatpak you want to recreate.

## Fresh install (high level)

1. Boot the **NixOS installer** ISO.
2. Partition, encrypt (LUKS) if you use it, format, mount. Run **`nixos-generate-config --root /mnt`**.
3. Clone this repository (or copy in `configuration.nix` and assets) under `/mnt/etc/nixos` or your chosen `NIXOS_CONFIG` location.
4. **Do not** blindly reuse the old **`hardware-configuration.nix`**. Start from the **new** `nixos-generate-config` output, then **merge** intentional settings from the previous machine:
   - `fileSystems` and **`boot.initrd.luks.devices`** (names and **UUIDs will change** with new disks/partitions)
   - `boot.initrd.availableKernelModules` / `kernelModules` as needed
   - `swapDevices` if applicable
5. This repo includes **Home Manager** (`./home.nix`, pinned in `configuration.nix` via `fetchTarball` on the `release-25.11` branch). It activates with **`sudo nixos-rebuild switch`** the same as the rest of the system. On a fresh clone, no extra `home-manager` install step is required. **User session env** may live in [`home.nix` via `home.sessionVariables`](./MIGRATION.md#home-manager-migration-log) (see log below). Grow **`home.nix`** further for more programs; **chezmoi** can stay in use for paths you have not moved—**one owner per path**.
6. In **`configuration.nix`**, update at least:
   - **`networking.hostName`** (e.g. old `Theseus` → new name)
   - **`<nixos-hardware/...>`** import when a profile exists for the **new** Framework model (path may differ from `framework/13-inch/amd-ai-300-series`); if none exists yet, comment the import and add hardware options manually.
   - **Kernel / boot**: Re-evaluate **`linuxPackages_latest`** and **`boot.kernelParams`** (e.g. `amd_pstate=active`) if the CPU is no longer the same (Intel vs AMD, etc.).
7. Set **`system.stateVersion`** to match your *first* NixOS install on the new box if the installer suggests a new default; do not advance casually (see NixOS manual).
8. Run **`sudo nixos-rebuild switch`** (or the flake equivalent) and reboot. That also runs **Home Manager** for user `wiz` (systemd `home-manager-wiz.service` or equivalent on your NixOS version).

## After first successful boot

1. **Fingerprint**: Re-enroll in Plasma settings (`fprintd`); hardware is a new device.
2. **WiFi**: Reconnect via NetworkManager (or add declarative connection files later).
3. **KWallet / wallet prompt**: If something prompts unexpectedly, it is often the same PAM/fingerprint/KWallet story as in the NixOS wiki; log in with **password** first, then align fingerprint in **Settings** if needed.
4. **VPN / stunnel**: Ensure **`/etc/...` paths** from `configuration.nix` (e.g. FrootVPN CA) exist; PEM is referenced from this repo in **`environment.etc`**, so a successful rebuild already places it.
5. **Chezmoi / dotfiles & Home Manager**: If you still use **chezmoi** for some paths, `chezmoi apply` is fine; if **`home.nix`** starts managing the same file, resolve the overlap (remove from chezmoi or drop the `home.file` in HM) to avoid clobbering. Prefer growing **`./home.nix`** on new hardware so the next migration is a single `git pull` + `nixos-rebuild`.
6. **Plymouth / SDDM**: After rebuild, log out to SDDM once to confirm **theme** and **login background** (`breeze-login`, `login-bg.png`).

## Optional: Framework setup roadmap (documentation)

A **vendored copy** of the Stellarium **NixOS on Framework** project may live in **`documentation/nixos-framework-setup/`** in this repository (full files, not symlinks, so clones stay portable). It is the **phased checklist** (LOCKED, audit, session, Home Manager, rice) — **documentation only**; it does not change `nixos-rebuild` by itself. If you also keep a copy under a Stellarium checkout (`projects/nixos-framework-setup/`, gitignored at the Stellarium root), **sync the trees manually** when you want them to match.

**Home Manager note:** this repo may include a **minimal** `home.nix` scaffold with the NixOS Home Manager module; **Phase D** in that roadmap (moving Kitty, zsh, git, etc. into `home.nix`) is still **deferred** until you choose to work it — see `documentation/nixos-framework-setup/06-implementation-checklist.md` and `LOCKED.md` there.

### Home Manager path ownership (audit, Theseus / `~/.config/nixos`)

Use **one owner per path**. Chezmoi source: typically `~/.local/share/chezmoi` (not this repo). Update **`.chezmoiignore`** when Nix or HM takes over a path.

| Path or topic | Current owner (typical) | Next HM / Nix step |
|---------------|-------------------------|--------------------|
| Session env (`EDITOR`, `TERMINAL`, `GIT_CONFIG_SYSTEM`, …) | [`home.nix`](./home.nix) | Done (step 1) |
| `fastfetch` CLI | `home.packages` in [`home.nix`](./home.nix) | Done (step 2 — proof) |
| `/etc/gitconfig` | NixOS `programs.git` in `configuration.nix` | Move to `programs.git` in `home.nix` later; then drop or slim system `programs.git` |
| `~/.zshrc` + Nix `programs.zsh` | NixOS + chezmoi (`zshconfig` alias) | Move `programs.zsh` to `home.nix` later; align chezmoi |
| `~/.config/kitty/kitty.conf` + `lilac-ash.conf` | HM `xdg.configFile` from [`kitty/`](./kitty/) in this repo; package via `home.packages` | **Done (step 3).** Remove chezmoi `dot_config/kitty` templates; add to **`.chezmoiignore`**, then `chezmoi apply` once. |
| `~/.config/fastfetch/config.jsonc` | User-edited, not in Nix | `xdg.configFile` or `programs.fastfetch` in HM later (optional) |
| `~/.config/obsidian` / `Cursor` / browser profiles | App defaults | Often stay imperative or app-managed |
| `chezmoi` tool | was `systemPackages` | Stays in `systemPackages` until moved to `home.packages` (optional) |
| `~/.config/newsboat`, `tmux`, etc. | Mixed | `programs.*` or `xdg` in HM in separate steps |

### Home Manager migration log

Iterative: **one** logical change per rebuild; **verify** before the next (see `documentation/nixos-framework-setup/` roadmap).

- **2026-04-17 — Step 1 (session env):** `home.sessionVariables` in `./home.nix` holds `EDITOR`, `SYSTEMD_EDITOR`, `VISUAL`, `TERMINAL`, `GIT_CONFIG_SYSTEM` (previously `environment.variables` + `environment.sessionVariables` in `configuration.nix`). Rebuild: `sudo nixos-rebuild switch`. **Verify:** new Kitty/Konsole: `echo "$EDITOR" "$TERMINAL"`, and `git config --list` still sees system config via `GIT_CONFIG_SYSTEM`.
- **2026-04-17 — Step 2 (proof package):** `fastfetch` moved from `environment.systemPackages` to `home.packages` in `./home.nix` (user `wiz` only). Rebuild: `sudo nixos-rebuild switch`. **Verify:** `command -v fastfetch` and `fastfetch` in a new login shell; `fetch` zsh alias still works.
- **2026-04-17 — Step 3 (Kitty):** `kitty` moved to `home.packages`; config from [`./kitty/kitty.conf`](./kitty/kitty.conf) + [`./kitty/lilac-ash.conf`](./kitty/lilac-ash.conf) via `xdg.configFile` in `./home.nix` (not `programs.kitty` — avoids a second generated `kitty.conf`). Removed `kitty` from `systemPackages`. `termconfig` alias now edits the **nixos repo** `kitty/` files. Rebuild: `sudo nixos-rebuild switch`. **Verify:** new Kitty; **Chezmoi:** delete or ignore `kitty` templates under `~/.local/share/chezmoi` and add the paths to **`.chezmoiignore`**, or `chezmoi` may overwrite `~/.config/kitty` until removed. If the first `switch` failed with *would be clobbered*, `home.nix` uses `force = true` on those `xdg` entries to replace existing files (back up first if you need the old `kitty.conf`).

## Optional: split machine-specific Nix

For less editing next time, you can add a small **`machine.nix`** (or gitignored `local.nix`) imported from `configuration.nix` that only sets **`hostName`**, **LUKS device entries**, and **nixos-hardware** import, keeping the main file shared across machines.

## Flakes (optional)

If you move to a **flake** + **`flake.lock`**, record that in a short “build command” note here (e.g. `nixos-rebuild switch --flake .#hostname`).

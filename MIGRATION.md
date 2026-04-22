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
5. In **`configuration.nix`**, update at least:
   - **`networking.hostName`** (e.g. old `Theseus` → new name)
   - **`<nixos-hardware/...>`** import when a profile exists for the **new** Framework model (path may differ from `framework/13-inch/amd-ai-300-series`); if none exists yet, comment the import and add hardware options manually.
   - **Kernel / boot**: Re-evaluate **`linuxPackages_latest`** and **`boot.kernelParams`** (e.g. `amd_pstate=active`) if the CPU is no longer the same (Intel vs AMD, etc.).
6. Set **`system.stateVersion`** to match your *first* NixOS install on the new box if the installer suggests a new default; do not advance casually (see NixOS manual).
7. Run **`sudo nixos-rebuild switch`** (or the flake equivalent) and reboot.

## After first successful boot

1. **Fingerprint**: Re-enroll in Plasma settings (`fprintd`); hardware is a new device.
2. **WiFi**: Reconnect via NetworkManager (or add declarative connection files later).
3. **KWallet / wallet prompt**: If something prompts unexpectedly, it is often the same PAM/fingerprint/KWallet story as in the NixOS wiki; log in with **password** first, then align fingerprint in **Settings** if needed.
4. **VPN / stunnel**: Ensure **`/etc/...` paths** from `configuration.nix` (e.g. FrootVPN CA) exist; PEM is referenced from this repo in **`environment.etc`**, so a successful rebuild already places it.
5. **Chezmoi / dotfiles**: Run your usual `chezmoi apply` (or init from your dotfile repo) so `~/.config` matches your expectations.
6. **Plymouth / SDDM**: After rebuild, log out to SDDM once to confirm **theme** and **login background** (`breeze-login`, `login-bg.png`).

## Optional: split machine-specific Nix

For less editing next time, you can add a small **`machine.nix`** (or gitignored `local.nix`) imported from `configuration.nix` that only sets **`hostName`**, **LUKS device entries**, and **nixos-hardware** import, keeping the main file shared across machines.

## Flakes (optional)

If you move to a **flake** + **`flake.lock`**, record that in a short “build command” note here (e.g. `nixos-rebuild switch --flake .#hostname`).

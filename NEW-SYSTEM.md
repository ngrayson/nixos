# New system setup (short)

This repo is the NixOS + [Home Manager](https://nix-community.github.io/home-manager/) config for user **`wiz`**. Releases and external modules are pinned by [`flake.nix`](./flake.nix) and [`flake.lock`](./flake.lock); named hosts are exposed under `nixosConfigurations`.

## 1. Install NixOS on the hardware

1. Boot the NixOS installer, partition, encrypt if you want LUKS, mount to `/mnt`.
2. Run **`nixos-generate-config --root /mnt`**. That produces a **new** `hardware-configuration.nix` for **this** machine only.
3. Clone this repository to your config path (e.g. `/mnt/etc/nixos` or `~/.config/nixos` after first boot). **Do not** copy an old `hardware-configuration.nix` from another PC; merge only deliberate bits (extra `kernelModules`, etc.) into the **new** generated file.

## 2. Add the named host

Create `hosts/<hostname>/configuration.nix`, `host.nix`, and the generated `hardware-configuration.nix`, then add the host to `nixosConfigurations` in [`flake.nix`](./flake.nix). The flake output name is case-sensitive and should match `networking.hostName`.

## 3. Machine-specific options: `hosts/<hostname>/`

Under **`hosts/<hostname>/`** for **this** machine:

- **`host.nix`**: **`networking.hostName`**, host-only modules, **`boot.initrd.luks.devices`**, **`boot.kernelParams`**
- **`hardware-configuration.nix`**: from **`nixos-generate-config`** for this host only
- **`configuration.nix`**: imports **`../../common/system.nix`**, `./hardware-configuration.nix`, `./host.nix`

Hardware modules from `nixos-hardware` belong in that host's module list in [`flake.nix`](./flake.nix), not in a channel-style `<nixos-hardware/...>` import.

Shared **system** options live in **[`common/system.nix`](./common/system.nix)**. Per-user **Home Manager** config: root **[`home.nix`](./home.nix)** imports the modular **[`./home/`](./home/)** directory ([`home/default.nix`](./home/default.nix) orchestrates `session.nix`, `programs/`, `wayland/`, `services/`, `xdg/`, etc.).

## 4. `system.stateVersion`

Set **`system.stateVersion`** in `hosts/<hostname>/host.nix` to the release used for that machine's **first** install. Do not bump it during routine NixOS upgrades.

## 5. Build and switch

Use the guided helper:

```bash
os-rebuild build --host <hostname>
os-rebuild dry-activate --host <hostname>
os-rebuild switch --host <hostname>
```

For a machine that should activate only after reboot, replace `switch` with `boot`. The equivalent direct command is:

```bash
sudo nixos-rebuild switch --flake ~/.config/nixos#<hostname>
```

Home Manager runs as part of that for **`wiz`** (no separate `home-manager switch` when using the NixOS HM module).

## 6. After boot

- Re-enrol **fingerprint**, reconnect **Wi‑Fi**, fix **VPN** paths if you use them (`environment.etc` in [`common/system.nix`](./common/system.nix)).
- **Cursor**: [CURSOR_SETUP.md](./CURSOR_SETUP.md) so `~/.local/bin/cursor` matches shell aliases in [`home/programs/zsh.nix`](./home/programs/zsh.nix).
- Custom **`.desktop`** files: already in [`desktop/applications/`](./desktop/applications/); they land in `~/.local/share/applications/` via Home Manager.
- **Kvantum (Qt):** add [`kvantum/<hostname>/`](./kvantum/README.md) matching **`networking.hostName`** in **`hosts/<hostname>/host.nix`**, and extend [`home/lib/host-xdg.nix`](./home/lib/host-xdg.nix) / [`home/xdg/config.nix`](./home/xdg/config.nix) if your theme includes extra paths beyond those already wired (see **Tawa** / **Theseus** under `kvantum/`).

## 7. Full detail and history

Use **[MIGRATION.md](./MIGRATION.md)** for a full checklist, migration log, and path-ownership table.
See **“Idle policy (lock / display off / suspend) + Slippi rule”** there for Hypridle timing and the Slippi emulation exception.

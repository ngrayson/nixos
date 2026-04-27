# New system setup (short)

This repo is the NixOS + [Home Manager](https://nix-community.github.io/home-manager/) config for user **`wiz`**. NixOS **25.11** and Home Manager **`release-25.11`** are assumed (see [`common/system.nix`](./common/system.nix)).

## 1. Install NixOS on the hardware

1. Boot the NixOS installer, partition, encrypt if you want LUKS, mount to `/mnt`.
2. Run **`nixos-generate-config --root /mnt`**. That produces a **new** `hardware-configuration.nix` for **this** machine only.
3. Clone this repository to your config path (e.g. `/mnt/etc/nixos` or `~/.config/nixos` after first boot). **Do not** copy an old `hardware-configuration.nix` from another PC; merge only deliberate bits (extra `kernelModules`, etc.) into the **new** generated file.

## 2. Point the install at this config

If the live config is not `/etc/nixos`, use `NIXOS_CONFIG` or `-I nixos-config=…` (see [`BRANCHING.md`](./BRANCHING.md) if you use a non-default path).

## 3. Machine-specific options: `hosts/<hostname>/`

Under **`hosts/<hostname>/`** for **this** machine:

- **`host.nix`**: **`networking.hostName`**, **`imports`** (`<nixos-hardware/…>`), **`boot.initrd.luks.devices`**, **`boot.kernelParams`**
- **`hardware-configuration.nix`**: from **`nixos-generate-config`** for this host only
- **`configuration.nix`**: imports **`../../common/system.nix`**, `./hardware-configuration.nix`, `./host.nix`

Set **`NIXOS_CONFIG`** to **`…/hosts/<hostname>/configuration.nix`**, or edit the root [`configuration.nix`](./configuration.nix) import if this host is the repo default.

Shared **system** options live in **[`common/system.nix`](./common/system.nix)**. Per-user **Home Manager** config: root **[`home.nix`](./home.nix)** imports the modular **[`./home/`](./home/)** directory ([`home/default.nix`](./home/default.nix) orchestrates `session.nix`, `programs/`, `wayland/`, `services/`, `xdg/`, etc.).

## 4. `system.stateVersion`

Set **`system.stateVersion`** in [`common/system.nix`](./common/system.nix) to what the **installer** recommends for a **first** install on this machine; see the NixOS manual before changing it later.

## 5. Build and switch

```bash
sudo nixos-rebuild switch
```

Home Manager runs as part of that for **`wiz`** (no separate `home-manager switch` when using the NixOS HM module).

## 6. After boot

- Re-enrol **fingerprint**, reconnect **Wi‑Fi**, fix **VPN** paths if you use them (`environment.etc` in [`common/system.nix`](./common/system.nix)).
- **Cursor**: [CURSOR_SETUP.md](./CURSOR_SETUP.md) so `~/.local/bin/cursor` matches shell aliases in [`home/programs/zsh.nix`](./home/programs/zsh.nix).
- Custom **`.desktop`** files: already in [`desktop/applications/`](./desktop/applications/); they land in `~/.local/share/applications/` via Home Manager.
- **Kvantum (Qt):** add [`kvantum/<hostname>/`](./kvantum/README.md) matching **`networking.hostName`** in **`hosts/<hostname>/host.nix`**, and extend [`home/lib/host-xdg.nix`](./home/lib/host-xdg.nix) / [`home/xdg/config.nix`](./home/xdg/config.nix) if your theme includes extra paths beyond those already wired (see **Tawa** / **Theseus** under `kvantum/`).

## 7. Full detail and history

Use **[MIGRATION.md](./MIGRATION.md)** for a full checklist, migration log, and path-ownership table.

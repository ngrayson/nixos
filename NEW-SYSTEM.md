# New system setup (short)

This repo is the NixOS + [Home Manager](https://nix-community.github.io/home-manager/) config for user **`wiz`**. NixOS **25.11** and Home Manager **`release-25.11`** are assumed (see `configuration.nix`).

## 1. Install NixOS on the hardware

1. Boot the NixOS installer, partition, encrypt if you want LUKS, mount to `/mnt`.
2. Run **`nixos-generate-config --root /mnt`**. That produces a **new** `hardware-configuration.nix` for **this** machine only.
3. Clone this repository to your config path (e.g. `/mnt/etc/nixos` or `~/.config/nixos` after first boot). **Do not** copy an old `hardware-configuration.nix` from another PC; merge only deliberate bits (extra `kernelModules`, etc.) into the **new** generated file.

## 2. Point the install at this config

If the live config is not `/etc/nixos`, use `NIXOS_CONFIG` or `-I nixos-config=…` (see [`BRANCHING.md`](./BRANCHING.md) if you use a non-default path).

## 3. Machine-specific options: `hostname.nix`

Edit **[`hostname.nix`](./hostname.nix)** (or swap the import in `configuration.nix` for another file) for **this** host:

- **`networking.hostName`**
- **`imports`**: `<nixos-hardware/…>` profile, or remove if no match
- **`boot.initrd.luks.devices`**: UUIDs and names must match **this** disk layout (see `hardware-configuration.nix` and any extra LUKS volumes, e.g. swap)
- **`boot.kernelParams`**: e.g. drop `amd_pstate=active` on Intel

Shared software and desktop stuff stay in **`configuration.nix`** and **`home.nix`**.

## 4. `system.stateVersion`

Set **`system.stateVersion`** in `configuration.nix` to what the **installer** recommends for a **first** install on this machine; see the NixOS manual before changing it later.

## 5. Build and switch

```bash
sudo nixos-rebuild switch
```

Home Manager runs as part of that for **`wiz`** (no separate `home-manager switch` when using the NixOS HM module).

## 6. After boot

- Re-enrol **fingerprint**, reconnect **Wi‑Fi**, fix **VPN** paths if you use them (`environment.etc` in `configuration.nix`).
- **Cursor**: [CURSOR_SETUP.md](./CURSOR_SETUP.md) so `~/.local/bin/cursor` matches `home.nix` shell aliases.
- Custom **`.desktop`** files: already in [`desktop/applications/`](./desktop/applications/); they land in `~/.local/share/applications/` via Home Manager.
- **Kvantum (Qt):** add [`kvantum/<hostname>/`](./kvantum/README.md) matching **`networking.hostName`** in [`hostname.nix`](./hostname.nix), and extend `home.nix` if your theme includes extra files beyond the Theseus example.

## 7. Full detail and history

Use **[MIGRATION.md](./MIGRATION.md)** for a full checklist, migration log, and path-ownership table.

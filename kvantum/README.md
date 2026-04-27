# Kvantum (per host)

- **`Kvantum/`** in `~/.config` is populated from **`./kvantum/<hostname>/`** in this repo, where **`<hostname>`** is `networking.hostName` in **`hosts/<hostname>/host.nix`** (e.g. **Tawa**).
- On a **new machine**, add a directory **`kvantum/<new-hostname>/`** with the same layout as the live `~/.config/Kvantum/` (at least `kvantum.kvconfig` and the theme dir you select in that file’s `theme=…`).
- After `nixos-rebuild`, keep **Plasma → Application Style** set to **Kvantum**; pick the theme in **Kvantum Manager** if needed.
- **Packages** (Qt5/6 Kvantum) remain in [`common/system.nix`](../common/system.nix) (`qtstyleplugin-kvantum`).

To capture from a running system:

```bash
mkdir -p kvantum/$(hostname) && cp -a ~/.config/Kvantum/. kvantum/$(hostname)/
```

Then add the corresponding `xdg.configFile` entries in `home.nix` (or extend the set there) for any new file paths.

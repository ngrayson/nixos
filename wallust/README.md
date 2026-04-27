# Wallust (live theming)

1. Set **`theme.dynamic = true`** in [`home.nix`](file:///home/wiz/.config/nixos/home.nix) (uncomment the line).
2. `sudo nixos-rebuild switch`
3. Run **`wallust-run /path/to/wallpaper.png`** (uses `~/.config/wallust` from this repo).
4. **`theme-reload`** re-runs Hyprland reload, kitty USR1, GTK gsettings nudge, restarts **Albert** (so Qt picks up the wallust palette), and touches **qt6ct** so running Qt apps can refresh.

**Qt (Albert, many third-party Qt apps):** Hyprland sets `env = QT_QPA_PLATFORMTHEME,qt6ct`, and Home Manager installs `~/.config/qt6ct/qt6ct.conf` (Fusion + `color_scheme_path` → `~/.config/qt6ct/colors/wallust.conf`). `qt6ct` must be installed (`theme.dynamic` adds it). If the qt6ct GUI still warns, log out and back in so the full session sees `QT_QPA_PLATFORMTHEME`.

**KDE / Kate with Plasma enabled:** Kate may follow **System Settings → Appearance** (Breeze) instead of qt6ct. Matching wallust there may require KDE’s own color schemes or Kvantum; qt6ct is most reliable for non-KDE Qt apps (e.g. Albert).

**Firefox:** NixOS sets the **system theme** preference so the browser chrome can follow GTK / `~/.config/gtk-*` (where wallust writes). You may still need to pick **System theme** once under **Settings → Themes** if the UI was on a built-in dark/light theme.

**Quickshell lock:** The lock surface reads the same **`WallustColors.qml`** as the bar (generated under `~/.config/quickshell/`). After changing templates, run **`wallust-run`** again so that file includes new keys (`onAccent`, `error`, etc.).

**Bake:** set `theme.dynamic = false`, copy final `WallustColors.qml` / kitty / hypr snippets into the repo, and point Stylix at a `themes/*.yaml` scheme.

See [`home/theme-dynamic.nix`](file:///home/wiz/.config/nixos/home/theme-dynamic.nix).

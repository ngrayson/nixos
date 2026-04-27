# Wallust (live theming)

1. Set **`theme.dynamic = true`** in [`home.nix`](file:///home/wiz/.config/nixos/home.nix) (uncomment the line).
2. `sudo nixos-rebuild switch`
3. Run **`wallust-run /path/to/wallpaper.png`** (uses `~/.config/wallust` from this repo).
4. **`theme-reload`** (after each `wallust run`) reloads Hyprland, nudges GTK, applies the **KDE color scheme** (`plasma-apply-colorscheme` + `kwriteconfig6` so **Dolphin/Kate** follow `~/.local/share/color-schemes/wallust.colors`), touches **qt6ct**, **restarts Quickshell** (so `WallustColors.qml` is re-read from disk), then **restarts Albert** with `QT_QPA_PLATFORMTHEME=qt6ct`.

**Qt (Albert, non-KDE Qt apps):** Hyprland sets `env = QT_QPA_PLATFORMTHEME,qt6ct`, and Home Manager installs `~/.config/qt6ct/qt6ct.conf` (Fusion + wallust `color_scheme_path`). Full session may need a re-login once for all launchers to see the variable.

**KDE (Dolphin, Kate, etc.):** Wallust writes **`wallust.colors`**; `theme-reload` sets **`ColorScheme=wallust`** in `~/.config/kdeglobals` and runs **`plasma-apply-colorscheme wallust`**. If a running Dolphin/Kate instance does not refresh, close and reopen it once (KDE does not always repaint every open window).

**Firefox:** NixOS sets the **system theme** preference so the browser chrome can follow GTK / `~/.config/gtk-*` (where wallust writes). You may still need to pick **System theme** once under **Settings → Themes** if the UI was on a built-in dark/light theme.

**Quickshell lock:** The lock surface reads the same **`WallustColors.qml`** as the bar (generated under `~/.config/quickshell/`). After changing templates, run **`wallust-run`** again so that file includes new keys (`onAccent`, `error`, etc.).

**Bake:** set `theme.dynamic = false`, copy final `WallustColors.qml` / kitty / hypr snippets into the repo, and point Stylix at a `themes/*.yaml` scheme.

See [`home/theme-dynamic.nix`](file:///home/wiz/.config/nixos/home/theme-dynamic.nix).

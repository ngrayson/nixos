# Wallust (live theming)

1. Set **`theme.dynamic = true`** in [`home.nix`](file:///home/wiz/.config/nixos/home.nix) (uncomment the line).
2. `sudo nixos-rebuild switch`
3. Run **`wallust-run /path/to/wallpaper.png`** (uses `~/.config/wallust` from this repo).
4. **`theme-reload`** (after each `wallust run`) reloads Hyprland, nudges GTK, updates **Dolphin/Kate** (writes `~/.local/share/color-schemes/wallust.colors`, sets **`[General]`** and **`[UiSettings]`** `ColorScheme=wallust` in `kdeglobals`, best-effort **`plasma-apply-colorscheme`**, clears a few **KDE caches**), touches **qt6ct**, then **restarts Quickshell via `hyprctl dispatch exec`** to the wallust relaunch script (Wayland + fresh QML; falls back to `nohup` if not on Hypr), then **restarts Albert** after **`pkill albert`**.

**Hyprland (not a KDE session):** There is no **plasmashell** or **kded** to push live theme updates. `plasma-apply-colorscheme` is tried but often useless here; **`kwriteconfig6`** and **cache `rm`** matter more. **Quickshell** only picks up new `WallustColors.qml` when its **process** restarts — we do that every `theme-reload`, not a repaint inside the same process.

**Qt (Albert) & `XDG_DATA_DIRS`:** With **`theme.dynamic`**, Home Manager sets **`xdg.systemDirs.data`** to prepend `~/.local/share` on **`XDG_DATA_DIRS`** so Nix-wrapped apps can see **`~/.local/share/color-schemes/wallust.colors`**. Hypr also sets `env = QT_QPA_PLATFORMTHEME,qt6ct`.

**KDE (Dolphin, Kate):** KF6 reads **`kdeglobals`** + the scheme file. If they still look like Breeze after `wallust-run`, **fully quit** the app (not only close windows) and start again, or log out once so the new **`XDG_DATA_DIRS`** is everywhere.

**Firefox:** NixOS sets the **system theme** preference so the browser chrome can follow GTK / `~/.config/gtk-*` (where wallust writes). You may still need to pick **System theme** once under **Settings → Themes** if the UI was on a built-in dark/light theme.

**Firefox:** NixOS sets the **system theme** preference so the browser chrome can follow GTK / `~/.config/gtk-*` (where wallust writes). You may still need to pick **System theme** once under **Settings → Themes** if the UI was on a built-in dark/light theme.

**Quickshell lock:** The lock surface reads the same **`WallustColors.qml`** as the bar (generated under `~/.config/quickshell/`). After changing templates, run **`wallust-run`** again so that file includes new keys (`onAccent`, `error`, etc.).

**Bake:** set `theme.dynamic = false`, copy final `WallustColors.qml` / kitty / hypr snippets into the repo, and point Stylix at a `themes/*.yaml` scheme.

See [`home/theme-dynamic.nix`](file:///home/wiz/.config/nixos/home/theme-dynamic.nix).

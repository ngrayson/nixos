# Wallust (live theming)

1. Set **`theme.dynamic = true`** in [`home.nix`](file:///home/wiz/.config/nixos/home.nix) (uncomment the line).
2. `sudo nixos-rebuild switch`
3. Run **`wallust-run /path/to/wallpaper.png`** (uses `~/.config/wallust` from this repo).
4. **`theme-reload`** re-runs Hyprland reload, kitty USR1, GTK gsettings nudge, qt6ct touch.

**Bake:** set `theme.dynamic = false`, copy final `WallustColors.qml` / kitty / hypr snippets into the repo, and point Stylix at a `themes/*.yaml` scheme.

See [`home/theme-dynamic.nix`](file:///home/wiz/.config/nixos/home/theme-dynamic.nix).

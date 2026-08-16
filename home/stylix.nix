# Stylix via Home Manager only. The module is supplied by the pinned flake input.
#
# Tawa: multi-monitor Izar wallpaper is handled by [`services/rwpspread-wallpaper.nix`](./services/rwpspread-wallpaper.nix),
# not Stylix Hyprpaper. Other hosts: Stylix preloads `stylix.image` as Hyprpaper fallback (`wallpaper = ,<path>`).
#
# GTK: Stylix uses theme name `adw-gtk3` (engine) plus generated `gtk.css` (Base16 colors) — `gsettings get
# org.gnome.desktop.interface gtk-theme` may show `adw-gtk3` while Izar palette still applies.
# Firefox “System theme” follows GTK/dconf; Stylix `targets.firefox` needs HM `programs.firefox` profiles +
# `stylix.targets.firefox.profileNames` (see Stylix installation docs / Firefox module).
{
  nixosConfig ? null,
  stylixModule,
  pkgs,
  config,
  lib,
  ...
}: let
  hostIsTawa = nixosConfig != null && nixosConfig.networking.hostName == "Tawa";
  wallpaperFile =
    if hostIsTawa
    then ../izar-utopia.png
    else ../login-bg.png;
  wallpaperName =
    if hostIsTawa
    then "izar-utopia.png"
    else "stylix-wallpaper.png";
in {
  imports = [stylixModule];

  stylix = {
    enable = true;
    # Explicit targets only (avoids surprise enables as Stylix adds defaults). See MIGRATION.md § Stylix.
    autoEnable = false;

    polarity = "dark";
    # Was `tokyo-night-dark`; Izar keeps Firefox/GTK/Stylix aligned with Hyprland + Kitty (chromamancer).
    base16Scheme = "${../themes/izar-base16.yaml}";
    image = builtins.path {
      path = wallpaperFile;
      name = wallpaperName;
    };

    fonts = {
      monospace = {
        package = pkgs.jetbrains-mono;
        name = "JetBrains Mono";
      };
      sansSerif = {
        package = pkgs.inter;
        name = "Inter Variable";
      };
      serif = {
        package = pkgs.source-serif;
        name = "Source Serif 4";
      };
      sizes = {
        applications = 11;
        terminal = 12;
        desktop = 10;
      };
    };

    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    targets = {
      fontconfig.enable = true;
      gtk.enable = true;

      kitty.enable = false;

      qt.enable = true;

      hyprland = {
        enable = true;
        hyprpaper.enable = !hostIsTawa;
      };
    };
  };

  # Stylix's `gtk` target only writes the theme + Base16 `gtk.css`; it never sets the freedesktop
  # appearance preference. Apps that follow the *system* setting (Electron/Chromium, Firefox "System
  # theme", libadwaita) read `org.gnome.desktop.interface color-scheme` through the settings portal, so
  # without this they render light on an otherwise dark desktop. HM maps this to dconf `prefer-dark`
  # plus `gtk-application-prefer-dark-theme` / `gtk-interface-color-scheme` in both settings.ini files.
  gtk.colorScheme = "dark";

  # Leftover files from the reverted Wallust experiment; not referenced by Stylix HM `gtk.css` but confuse
  # inspection and could interact badly if GTK ever loads them from the config dir.
  home.activation.stylixRemoveStaleGtkCss = lib.hm.dag.entryAfter ["writeBoundary"] ''
    for f in \
      "${config.home.homeDirectory}/.config/gtk-3.0/wallust-colors.css" \
      "${config.home.homeDirectory}/.config/gtk-4.0/wallust-colors.css" \
      "${config.home.homeDirectory}/.config/gtk-3.0/colors.css" \
      "${config.home.homeDirectory}/.config/gtk-4.0/colors.css"
    do
      if [ -f "$f" ] && [ ! -L "$f" ]; then
        $DRY_RUN_CMD rm -f "$f"
      fi
    done
  '';
}

# Stylix via Home Manager only (no flakes): https://nix-community.github.io/stylix/installation.html
# Use `builtins.fetchTarball` here (not `pkgs.fetchFromGitHub`) so `imports` does not force `pkgs`
# before Home Manager has finished fixing up `_module.args` (avoids infinite recursion).
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
  pkgs,
  config,
  lib,
  ...
}: let
  # Match `home-manager` release-25.11 (see Stylix install docs for stable + HM).
  stylixSrc = builtins.fetchTarball {
    url = "https://github.com/nix-community/stylix/archive/release-25.11.tar.gz";
    sha256 = "1pcldghrbln6pnbph990871442zkfa7vmzmqgh9x62ijjgbzvr62";
  };
  stylix = import stylixSrc;
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
  imports = [stylix.homeModules.stylix];

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

      qt.enable = false;

      hyprland = {
        enable = true;
        hyprpaper.enable = !hostIsTawa;
      };
    };
  };

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

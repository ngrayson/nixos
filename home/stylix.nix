# Stylix via Home Manager only (no flakes): https://nix-community.github.io/stylix/installation.html
# Use `builtins.fetchTarball` here (not `pkgs.fetchFromGitHub`) so `imports` does not force `pkgs`
# before Home Manager has finished fixing up `_module.args` (avoids infinite recursion).
{pkgs, ...}: let
  # Match `home-manager` release-25.11 (see Stylix install docs for stable + HM).
  stylixSrc = builtins.fetchTarball {
    url = "https://github.com/nix-community/stylix/archive/release-25.11.tar.gz";
    sha256 = "1pcldghrbln6pnbph990871442zkfa7vmzmqgh9x62ijjgbzvr62";
  };
  stylix = import stylixSrc;
in {
  imports = [stylix.homeModules.stylix];

  stylix = {
    enable = true;
    autoEnable = false;

    polarity = "dark";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyo-night-dark.yaml";
    image = builtins.path {
      path = ../login-bg.png;
      name = "stylix-wallpaper.png";
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
        hyprpaper.enable = true;
      };
    };
  };
}

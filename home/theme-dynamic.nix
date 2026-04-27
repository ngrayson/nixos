# Optional Wallust live theming. Set `theme.dynamic = true` (e.g. in `home.nix`).
# Run: `wallust-run /path/to/image.png`
{
  config,
  lib,
  pkgs,
  ...
}: let
  wallustDir = ../wallust;
  tmplDir = ../wallust/templates;
  tmplNames = builtins.attrNames (builtins.readDir tmplDir);
  tmplFiles = builtins.listToAttrs (
    map (n: {
      name = "wallust/templates/${n}";
      value = {source = tmplDir + "/${n}";};
    })
    tmplNames
  );
  theme-reload = pkgs.writeShellScriptBin "theme-reload" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [pkgs.hyprland]}:$PATH"
    hyprctl reload 2>/dev/null || true
    ${pkgs.procps}/bin/pkill -SIGUSR1 kitty 2>/dev/null || true
    if command -v gsettings >/dev/null; then
      raw=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo "'Adwaita'")
      gsettings set org.gnome.desktop.interface gtk-theme Adwaita 2>/dev/null || true
      sleep 0.25
      gsettings set org.gnome.desktop.interface gtk-theme "$raw" 2>/dev/null || true
    fi
    touch "''${HOME}/.config/qt6ct/qt6ct.conf" 2>/dev/null || true
  '';
  wallust-run = pkgs.writeShellScriptBin "wallust-run" ''
    set -euo pipefail
    if [ "$#" -lt 1 ]; then
      echo "usage: wallust-run /path/to/image.png" >&2
      exit 1
    fi
    img="$1"
    ${pkgs.wallust}/bin/wallust run "$img" -d "''${HOME}/.config/wallust"
    exec ${theme-reload}/bin/theme-reload
  '';
in {
  options.theme.dynamic = lib.mkEnableOption ''
    Wallust-driven GTK/Hyprland/Kitty/Qt/Quickshell colors.
    When true, Stylix Hyprland + GTK theming are disabled (fonts/cursor/fontconfig unchanged).
  '';

  config = lib.mkMerge [
    {
      # Always on PATH; Hypr/GTK/Stylix wiring still follows `theme.dynamic`.
      home.packages = [pkgs.wallust theme-reload wallust-run];

      xdg.configFile =
        {
          "wallust/wallust.toml".source = wallustDir + "/wallust.toml";
        }
        // tmplFiles;

      home.file.".config/kitty/wallust-colors.conf".text = "# optional wallust palette (theme.dynamic)\n";
    }

    (lib.mkIf config.theme.dynamic {
      home.packages = [pkgs.qt6Packages.qt6ct];

      home.file.".config/hypr/wallust/colors.conf".text = "# run wallust-run to generate colors\n";

      services.hyprpaper = {
        enable = true;
        package = pkgs.hyprpaper;
        settings = let
          wp = builtins.path {
            path = ../login-bg.png;
            name = "hyprpaper-wallust.png";
          };
        in {
          preload = ["${wp}"];
          wallpaper = [",${wp}"];
          splash = false;
        };
      };

      xdg.configFile = {
        "gtk-3.0/gtk.css".text = "@import 'wallust-colors.css';";
        "gtk-4.0/gtk.css".text = "@import 'wallust-colors.css';";
      };
    })
  ];
}

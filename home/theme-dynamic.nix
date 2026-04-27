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
  # `pkill -x` misses some binaries; relaunch on Wayland via Hypr (not bare nohup).
  quickshellRelaunch = pkgs.writeShellScript "wallust-quickshell" ''
    set -euo pipefail
    export QT_QPA_PLATFORMTHEME=qt6ct
    : "''${WAYLAND_DISPLAY:=}"
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    exec ${lib.getExe pkgs.quickshell} -d -p "''${HOME}/.config/quickshell"
  '';
  # Hyprland: no plasmashell/dbus; plasma-apply-colorscheme is best-effort only.
  applyKdeColors = ''
    _KW=${pkgs.kdePackages.kconfig}/bin/kwriteconfig6
    mkdir -p "''${HOME}/.local/share/color-schemes" "''${HOME}/.config"
    if [ -f "''${HOME}/.local/share/color-schemes/wallust.colors" ]; then
      ${pkgs.kdePackages.plasma-workspace}/bin/plasma-apply-colorscheme wallust 2>/dev/null || true
      # Both groups are read by KF6 apps; UiSettings is often what non-Plasma sessions miss.
      "$_KW" --file "''${HOME}/.config/kdeglobals" --group General --key ColorScheme --notify wallust 2>/dev/null || true
      "$_KW" --file "''${HOME}/.config/kdeglobals" --group UiSettings --key ColorScheme --notify wallust 2>/dev/null || true
      # Encourage a clean read of scheme files on next launch (no kded in pure Hyprland).
      rm -rf "''${HOME}"/.cache/kcolor* 2>/dev/null || true
      rm -rf "''${HOME}"/.cache/plasma* 2>/dev/null || true
      rm -rf "''${HOME}"/.cache/kde* 2>/dev/null || true
    fi
  '';
  theme-reload = pkgs.writeShellScriptBin "theme-reload" (''
      set -euo pipefail
      export PATH="${lib.makeBinPath [pkgs.hyprland pkgs.albert]}:$PATH"
      export QT_QPA_PLATFORMTHEME=qt6ct
      : "''${WAYLAND_DISPLAY:=}"
      : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
      export WAYLAND_DISPLAY
      export XDG_RUNTIME_DIR
      hyprctl reload 2>/dev/null || true
      ${pkgs.procps}/bin/pkill -SIGUSR1 kitty 2>/dev/null || true
      if command -v gsettings >/dev/null; then
        raw=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo "'Adwaita'")
        gsettings set org.gnome.desktop.interface gtk-theme Adwaita 2>/dev/null || true
        sleep 0.25
        gsettings set org.gnome.desktop.interface gtk-theme "$raw" 2>/dev/null || true
      fi
    ''
    + lib.optionalString config.theme.dynamic (applyKdeColors
      + ''
        touch "''${HOME}/.config/qt6ct/qt6ct.conf" 2>/dev/null || true
        ${pkgs.procps}/bin/pkill -f "quickshell" 2>/dev/null || true
        for _w in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
          ${pkgs.procps}/bin/pgrep -f quickshell >/dev/null 2>&1 && sleep 0.1 || break
        done
        if command -v hyprctl >/dev/null 2>&1 && ${pkgs.hyprland}/bin/hyprctl activeworkspace >/dev/null 2>&1; then
          ${pkgs.hyprland}/bin/hyprctl dispatch exec ${quickshellRelaunch} 2>/dev/null || { nohup ${quickshellRelaunch} >/dev/null 2>&1 & }
        else
          nohup ${quickshellRelaunch} >/dev/null 2>&1 &
        fi
      '')
    + ''
      ${pkgs.procps}/bin/pkill albert 2>/dev/null || true
      sleep 0.1
      nohup env QT_QPA_PLATFORMTHEME=qt6ct ${lib.getExe pkgs.albert} >/dev/null 2>&1 &
    '');
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

      # Do not use `home.file` for paths wallust overwrites — those become read-only
      # symlinks into the store. Replace broken symlinks / missing files after HM runs.
      home.activation.wallustWritableTargets = lib.hm.dag.entryAfter ["writeBoundary"] (
        ''
          set -euo pipefail
          _stub() {
            _path="$1"
            _line="$2"
            mkdir -p "$(dirname "$_path")"
            if [ -L "$_path" ] || [ ! -f "$_path" ]; then
              rm -f "$_path"
              printf '%s\n' "$_line" > "$_path"
            fi
          }
          _stub "${config.home.homeDirectory}/.config/kitty/wallust-colors.conf" \
            "# wallust palette — generated by wallust-run"
        ''
        + lib.optionalString config.theme.dynamic ''
          _stub "${config.home.homeDirectory}/.config/hypr/wallust/colors.conf" \
            "# wallust hypr — generated by wallust-run"
        ''
      );
    }

    (lib.mkIf config.theme.dynamic {
      home.packages = [pkgs.qt6Packages.qt6ct];

      home.sessionVariables = {
        QT_QPA_PLATFORMTHEME = "qt6ct";
      };

      # So Nix-wrapped Qt/KDE apps resolve ~/.local/share/color-schemes/wallust.colors
      xdg.systemDirs.data = ["${config.home.homeDirectory}/.local/share"];

      # Fusion + custom palette; wallust writes ~/.config/qt6ct/colors/wallust.conf
      xdg.configFile = {
        "qt6ct/qt6ct.conf".text = ''
          [Appearance]
          custom_palette=true
          standard_dialogs=default
          style=Fusion
          color_scheme_path=${config.home.homeDirectory}/.config/qt6ct/colors/wallust.conf
        '';
        "gtk-3.0/gtk.css".text = "@import 'wallust-colors.css';";
        "gtk-4.0/gtk.css".text = "@import 'wallust-colors.css';";
      };

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
    })
  ];
}

# Themed dunst from `config.theme.hex`. Click invokes the FreeDesktop default action.
# Quickshell keeps volume/brightness OSD; dunst is for async desktop notifications only.
{
  config,
  lib,
  pkgs,
  ...
}: let
  hx = config.theme.hex;
  xdgOpen = lib.getExe' pkgs.xdg-utils "xdg-open";
  hyprctl = lib.getExe' pkgs.hyprland "hyprctl";
  lastAppFile = "${config.home.homeDirectory}/.cache/qs-dunst-last-app";

  # dunst scripts get: appname summary body icon urgency
  trackLastApp = pkgs.writeShellScriptBin "qs-dunst-track-app" ''
    set -euo pipefail
    mkdir -p "$(dirname ${lib.escapeShellArg lastAppFile})"
    printf '%s\n' "''${1:-}" > ${lib.escapeShellArg lastAppFile}
  '';

  # Fallback when do_action has no FreeDesktop action: focus a window matching appname.
  # Also wraps fuzzel so multi-action context menus appear on the overlay layer.
  dunstMenu = pkgs.writeShellScriptBin "qs-dunst-menu" ''
    set -euo pipefail
    fuzzel=${lib.getExe pkgs.fuzzel}
    hyprctl=${lib.escapeShellArg hyprctl}
    last_file=${lib.escapeShellArg lastAppFile}

    input="$(cat || true)"
    if [[ -n "''${input//[$' \t\r\n']/}" ]]; then
      printf '%s\n' "$input" | "$fuzzel" -d --layer=overlay -p dunst
      exit $?
    fi

    app=""
    if [[ -f "$last_file" ]]; then
      app="$(tr '[:upper:]' '[:lower:]' <"$last_file" | tr -d '[:space:]')"
    fi
    [[ -n "$app" ]] || exit 0

    case "$app" in
      discord|discord-canary|com.discordapp.discord) class_re='discord' ;;
      element|element-desktop|im.riot.riot) class_re='element' ;;
      slack|com.slack.slack) class_re='slack' ;;
      signal|signal-desktop|org.signal.signal) class_re='signal' ;;
      firefox|org.mozilla.firefox) class_re='firefox' ;;
      *) class_re="$app" ;;
    esac

    "$hyprctl" dispatch focuswindow "class:(?i)$class_re" >/dev/null 2>&1 \
      || "$hyprctl" dispatch focuswindow "initialClass:(?i)$class_re" >/dev/null 2>&1 \
      || "$hyprctl" dispatch focuswindow "title:(?i)$class_re" >/dev/null 2>&1 \
      || true
  '';
in {
  home.packages = [pkgs.fuzzel dunstMenu trackLastApp];

  services.dunst = {
    enable = true;
    # Breeze ships dialog-* under status/22|64 (not hicolor/32x32); recursive lookup
    # uses the theme index instead of HM's flat icon_path.
    iconTheme = {
      name = "breeze-dark";
      package = pkgs.kdePackages.breeze-icons;
      size = "64x64";
    };
    settings = {
      global = {
        # Match Hyprland decoration.rounding (squircles via rounding_power are not available).
        corner_radius = 25;
        frame_width = 2;
        gap_size = 8;
        width = 360;
        origin = "top-right";
        # Under Quickshell top bar (32px) + gaps_out (~15).
        offset = "(15, 50)";

        font = "IosevkaTermSlab NF 11";
        background = hx.depth;
        foreground = hx.text;
        frame_color = hx.accent;
        separator_color = "frame";

        enable_recursive_icon_lookup = true;
        icon_theme = "breeze-dark, breeze, hicolor";
        icon_position = "left";
        max_icon_size = 48;
        min_icon_size = 32;

        # Laptop (no reliable middle-click):
        # left  = default action (raises app; needs Hyprland focus_on_activate)
        #         or context / focus fallback via qs-dunst-menu
        # right = dismiss
        mouse_left_click = "do_action";
        mouse_right_click = "close_current";
        mouse_middle_click = "close_all";

        dmenu = lib.getExe dunstMenu;
        browser = xdgOpen;
        always_run_script = true;
      };

      # Remember sender so empty-action left-clicks can still focus the app window.
      track_last_app = {
        appname = "*";
        script = lib.getExe trackLastApp;
      };

      urgency_low = {
        background = hx.depth;
        foreground = hx.muted;
        frame_color = hx.muted;
        timeout = 4;
      };

      urgency_normal = {
        background = hx.depth;
        foreground = hx.text;
        frame_color = hx.accent;
        timeout = 8;
      };

      urgency_critical = {
        background = hx.surface;
        foreground = hx.strong;
        frame_color = hx.error;
        timeout = 0;
      };
    };
  };
}

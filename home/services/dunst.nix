# Themed dunst from `config.theme.hex`. Click invokes the FreeDesktop default action.
# Quickshell keeps volume/brightness OSD; dunst is for async desktop notifications only.
{
  config,
  lib,
  pkgs,
  ...
}: let
  hx = config.theme.hex;
  fuzzel = lib.getExe pkgs.fuzzel;
  xdgOpen = lib.getExe' pkgs.xdg-utils "xdg-open";
in {
  home.packages = [pkgs.fuzzel];

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
        # left  = invoke default action (or action menu if none) — do NOT chain close
        # right = dismiss
        mouse_left_click = "do_action";
        mouse_right_click = "close_current";
        mouse_middle_click = "close_all";

        # overlay layer so the menu isn't buried under the notification window
        dmenu = "${fuzzel} -d --layer=overlay -p dunst";
        browser = xdgOpen;
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

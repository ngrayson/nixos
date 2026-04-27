# Hyprland: enable NixOS `programs.hyprland` in `common/system.nix`. `package` / `portalPackage` = null.
{
  config,
  lib,
  nixosConfig ? null,
  pkgs,
  ...
}: let
  hs = import ../hypr/scripts.nix {inherit config lib pkgs;};
  hx = import ../lib/host-xdg.nix {inherit lib nixosConfig;};
in {
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    systemd.enable = true;
    systemd.variables = ["--all"];
    xwayland.enable = true;
    settings = {
      "$mod" = "SUPER";
      general = {
        gaps_in = 4;
        gaps_out = 8;
        border_size = 2;
      };
      decoration = {
        rounding = 8;
      };
      input = {
        kb_layout = "us";
        follow_mouse = 1;
      };
      bind = [
        "ALT, h, movefocus, l"
        "ALT, j, movefocus, d"
        "ALT, k, movefocus, u"
        "ALT, l, movefocus, r"
        "ALT SHIFT, h, movewindow, l"
        "ALT SHIFT, j, movewindow, d"
        "ALT SHIFT, k, movewindow, u"
        "ALT SHIFT, l, movewindow, r"
        "ALT, Return, exec, ${pkgs.kitty}/bin/kitty"
        "ALT, escape, killactive,"
        "ALT SHIFT, Q, killactive,"
        "ALT, Space, exec, ${lib.getExe pkgs.albert} toggle"
        "ALT, 1, workspace, 1"
        "ALT, 2, workspace, 2"
        "ALT, 3, workspace, 3"
        "ALT, 4, workspace, 4"
        "ALT, 5, workspace, 5"
        "ALT, 6, workspace, 6"
        "ALT SHIFT, 1, movetoworkspace, 1"
        "ALT SHIFT, 2, movetoworkspace, 2"
        "ALT SHIFT, 3, movetoworkspace, 3"
        "ALT SHIFT, 4, movetoworkspace, 4"
        "ALT SHIFT, 5, movetoworkspace, 5"
        "ALT SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, E, exit,"
        "$mod, F, fullscreen, 0"
        "$mod SHIFT, Space, togglefloating,"
        "$mod, Y, togglesplit"
        "$mod SHIFT, P, pseudo"
        "$mod SHIFT, S, exec, ${lib.getExe hs.hyprScreenshotRegion}"
        "$mod, L, exec, ${lib.getExe hs.quickshellLock}"
        "$mod, B, exec, ${lib.getExe pkgs.firefox}"
        "$mod, D, exec, ${lib.getExe pkgs.discord}"
        "$mod, O, exec, ${lib.getExe pkgs.obsidian}"
        "$mod CTRL, h, resizeactive, -40 0"
        "$mod CTRL, j, resizeactive, 0 40"
        "$mod CTRL, k, resizeactive, 0 -40"
        "$mod CTRL, l, resizeactive, 40 0"
        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up, workspace, e-1"
        "$mod, bracketleft, workspace, m-1"
        "$mod, bracketright, workspace, m+1"
        "$mod, Tab, cyclenext"
        "$mod SHIFT, Tab, cyclenext, prev"
        ", Print, exec, ${lib.getExe hs.hyprScreenshotRegion}"
      ];
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
      "exec-once" = [
        "${lib.getExe pkgs.albert}"
        "${lib.getExe pkgs.dunst}"
        "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"
        "${lib.getExe pkgs.quickshell} -d -p ${hs.quickshellConfigDir}"
      ];
    };
    extraConfig =
      if hx.hyprMonitorsConf == null
      then ""
      else ''
        source = ${config.home.homeDirectory}/.config/hypr/monitors.conf
      '';
  };
}

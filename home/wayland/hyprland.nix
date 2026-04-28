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
  # Must match dirs in ../session.nix (`xdg.systemDirs.data`). Hypr subprocesses (`exec-once`),
  # including Albert, inherit the compositor env — SDDM/login does not reliably set these on NixOS.
  xdgDataDirsShare = lib.concatStringsSep ":" [
    "${config.home.homeDirectory}/.local/share"
    "${config.home.profileDirectory}/share"
    "/run/current-system/sw/share"
  ];
in {
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    systemd.enable = true;
    systemd.variables = ["--all"];
    xwayland.enable = true;
    settings = {
      # Ensure compositor children (and --all dbus import) see platform theme; qt6ct GUI checks this.
      env = [
        "QT_QPA_PLATFORMTHEME,kde"
        "XDG_DATA_DIRS,${xdgDataDirsShare}"
      ];
      "$mod" = "SUPER";
      general = {
        gaps_in = 10;
        gaps_out = 15;
        border_size = 2;
        # Izar (chromamancer themes/izar): overrides Stylix Hyprland `col.*`
        "col.active_border" = lib.mkForce "rgba(6abab5ff)";
        "col.inactive_border" = lib.mkForce "rgba(302947ff)";
      };
      decoration = {
        rounding = 25;
        rounding_power = 1.2;
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
        "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd --all"
        "${lib.getExe pkgs.albert}"
        "${lib.getExe pkgs.dunst}"
        "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"
        "${lib.getExe pkgs.quickshell} -d -p ${hs.quickshellConfigDir}"
      ];
    };
    extraConfig = (
      if hx.hyprMonitorsConf == null
      then ""
      else ''
        source = ${config.home.homeDirectory}/.config/hypr/monitors.conf
      ''
    );
  };
}

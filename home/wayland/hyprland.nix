# Hyprland: enable NixOS `programs.hyprland` in `common/system.nix`. `package` / `portalPackage` = null.
{
  config,
  lib,
  nixosConfig ? null,
  pkgs,
  ...
}: let
  hs = import ../hypr/scripts.nix {inherit config lib pkgs;};
  hx = import ../lib/host-xdg.nix {inherit lib nixosConfig pkgs;};
  hostName =
    if nixosConfig == null
    then ""
    else nixosConfig.networking.hostName;
  # Hearth keeps Albert (launcher) but not Discord / Obsidian.
  workstationBinds = hostName != "Hearth";
  # Match Quickshell top bar height in ../quickshell/shell.qml (`topBarHeight`).
  quickshellTopBarPx = 32;
  pavuTopGutterPx = 20;
  pavuRightGutterPx = 20;
  pavuWindowY = pavuTopGutterPx + quickshellTopBarPx;
  pavuWindowW = 900;
  pavuWindowH = 600;
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
    # Preserve the existing Hyprland syntax while home.stateVersion remains 25.11.
    configType = "hyprlang";
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
        # Mirrors `environment.sessionVariables` in common/system.nix. plasma6 ships only
        # `plasma-applications.menu`, so kbuildsycoca6 builds an empty menu without this and
        # KDE "Open With" dialogs list no applications.
        "XDG_MENU_PREFIX,plasma-"
      ];
      "$mod" = "SUPER";
      general = {
        gaps_in = 10;
        gaps_out = 15;
        border_size = 2;
        # Active scheme (home/theme/hosts.nix): overrides Stylix Hyprland `col.*`
        "col.active_border" = lib.mkForce "rgba(${lib.toLower config.theme.tokens.accent}ff)";
        "col.inactive_border" = lib.mkForce "rgba(${lib.toLower config.theme.tokens.surface}ff)";
      };
      decoration = {
        rounding = 25;
        rounding_power = 1.2;
      };
      dwindle = {
        # Keep the orientation chosen by `layoutmsg, togglesplit` when new windows open.
        preserve_split = true;
      };
      input =
        {
          kb_layout = "us";
          follow_mouse = 1;
        }
        // lib.optionalAttrs (hostName == "Theseus") {
          touchpad = {
            natural_scroll = true;
            disable_while_typing = true;
            tap-to-click = true;
          };
        };
      # Needed so notification default-actions (Discord, etc.) can raise their window.
      misc = {
        focus_on_activate = true;
      };
      bind =
        [
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
          "ALT, 7, workspace, 7"
          "ALT, 8, workspace, 8"
          "ALT, 9, workspace, 9"
          "ALT, 0, workspace, 10"
          "ALT SHIFT, 1, movetoworkspace, 1"
          "ALT SHIFT, 2, movetoworkspace, 2"
          "ALT SHIFT, 3, movetoworkspace, 3"
          "ALT SHIFT, 4, movetoworkspace, 4"
          "ALT SHIFT, 5, movetoworkspace, 5"
          "ALT SHIFT, 6, movetoworkspace, 6"
          "ALT SHIFT, 7, movetoworkspace, 7"
          "ALT SHIFT, 8, movetoworkspace, 8"
          "ALT SHIFT, 9, movetoworkspace, 9"
          "ALT SHIFT, 0, movetoworkspace, 10"
          "$mod SHIFT, E, exit,"
          "$mod, F, fullscreen, 0"
          "$mod SHIFT, Space, togglefloating,"
          "$mod, Y, layoutmsg, togglesplit"
          "$mod SHIFT, P, pseudo"
          "$mod SHIFT, S, exec, ${lib.getExe hs.hyprScreenshotRegion}"
          "$mod, L, exec, ${lib.getExe hs.quickshellLock}"
          "$mod SHIFT, L, exec, ${lib.getExe hs.quickshellLockPreview}"
          "$mod, B, exec, ${lib.getExe pkgs.firefox}"
          "$mod SHIFT, C, exec, ${lib.getExe pkgs.hyprpicker} -a -n"
        ]
        ++ lib.optionals workstationBinds [
          "$mod, D, exec, ${lib.getExe pkgs.discord}"
          "$mod, O, exec, ${lib.getExe pkgs.obsidian}"
        ]
        ++ [
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
          ", XF86AudioRaiseVolume, exec, sh -lc '${lib.getExe pkgs.pamixer} -i 5; ${lib.getExe hs.hyprQuickshellIpc} call audio notifyChange'"
          ", XF86AudioLowerVolume, exec, sh -lc '${lib.getExe pkgs.pamixer} -d 5; ${lib.getExe hs.hyprQuickshellIpc} call audio notifyChange'"
          ", XF86AudioMute, exec, sh -lc '${lib.getExe pkgs.pamixer} -t; ${lib.getExe hs.hyprQuickshellIpc} call audio notifyChange'"
          ", XF86AudioMicMute, exec, ${lib.getExe pkgs.pamixer} --default-source -t"
        ]
        ++ lib.optionals (hostName == "Theseus") [
          ", XF86MonBrightnessUp, exec, ${lib.getExe pkgs.brightnessctl} -c backlight set +5%"
          ", XF86MonBrightnessDown, exec, ${lib.getExe pkgs.brightnessctl} -c backlight set 5%-"
        ];
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
      # Locked (inhibitors): short power still reaches us. logind HandlePowerKey is ignore;
      # long-press stays kernel/logind poweroff. Locked session: IPC is a no-op (lock has its own row).
      bindl = [
        ", XF86PowerOff, exec, ${lib.getExe hs.hyprQuickshellIpc} call power toggle"
      ];
      # Pixel Composer (YoYo AppImage): WM_CLASS is empty under XWayland (see `hyprctl clients`); match titles.
      windowrule = [
        # Armored Core VI (1888160): no Hyprland chrome; avoids rounding/border on fullscreen game.
        "match:class ^(steam_app_1888160)$, border_size 0, rounding 0, no_shadow on"
        "match:title ^Pixel Composer.*, float on"
        "match:title ^Select files$, float on"
        "match:class ^(PixelComposer|pixelcomposer).*, float on"
        # `move` takes monitor-local math expressions; expressions may not contain spaces.
        # Since 0.54 `move` reads the pre-`size` width, so `window_w` lands the window wrong
        # (hyprwm/Hyprland#13409); offset by the known width instead.
        "match:class ^(org\\.pulseaudio\\.pavucontrol|pavucontrol)$, float on, size ${toString pavuWindowW} ${toString pavuWindowH}, move (monitor_w-${toString (pavuWindowW + pavuRightGutterPx)}) ${toString pavuWindowY}"
      ];
      "exec-once" = [
        "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd --all"
        # albert: `../programs/albert.nix` (systemd user unit), not exec-once.
        # dunst: Home Manager `services.dunst` (systemd user unit), not exec-once.
        # polkit-kde agent: `../services/polkit-agent.nix` (systemd user unit), not exec-once —
        # exec-once pins it to the session's original store path and never restarts it.
        "${lib.getExe pkgs.quickshell} -d -p ${hs.quickshellLiveDir}"
      ];
    };
    extraConfig =
      (
        if hx.hyprMonitorsConf == null
        then ""
        else ''
          source = ${config.home.homeDirectory}/.config/hypr/monitors.conf
        ''
      )
      + ''
        # Non-consuming: Escape still reaches apps; closes pavucontrol when that window is focused.
        bindn = , escape, exec, ${lib.getExe hs.pavuEscapeClose}

        # Palm rejection (Theseus) makes it impossible to hold SUPER while
        # dragging with the pen, so the $mod+drag gestures in `bindm` above are
        # unreachable there. This submap exposes the same two dispatchers with
        # nothing held: SUPER+A toggles in, Escape or SUPER+A again toggles out.
        # `resizewindow` picks the nearest edge from the click point, so the
        # whole window is the target -- there is no border strip to hit.
        #
        # This lives in extraConfig rather than `settings` because a submap is
        # positional: every bind after `submap = NAME` belongs to that submap
        # until `submap = reset`, and the attrset generator gives no ordering
        # guarantee. Keep this block last, and keep the trailing `submap =
        # reset` -- without it, anything appended later would silently land
        # inside the submap instead of the global keymap.
        bind = $mod, A, submap, resize-move
        submap = resize-move
        bindm = , mouse:272, movewindow
        bindm = , mouse:273, resizewindow
        bind = , escape, submap, reset
        bind = $mod, A, submap, reset
        submap = reset
      '';
  };

  home.packages = [
    hs.pavuToggle
    hs.pavuEscapeClose
    hs.hyprTrayFocus
    hs.hyprNixosStatus
    hs.hyprNixosTerm
    hs.hyprUsbStatus
    hs.hyprUsbEject
    hs.hyprUsbOpen
    hs.hyprQuickshellReload
    hs.hyprQuickshellIpc
    hs.hyprDpmsSideOff
    hs.hyprDpmsSideOn
  ];
}

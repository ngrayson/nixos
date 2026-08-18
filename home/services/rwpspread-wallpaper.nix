# Tawa (and any host with `spanMonitors`): span `config.theme.wallpaper` via rwpspread
# (`-b hyprpaper`). Stylix Hyprpaper is off when `theme.spanMonitors` is true.
{
  config,
  lib,
  pkgs,
  ...
}: let
  wallpaper = builtins.path {
    path = config.theme.wallpaper;
    name = config.theme.wallpaperName;
  };
  outDir = "${config.home.homeDirectory}/.cache/rwpspread";
in
  lib.mkIf (config.theme.spanMonitors && config.wayland.windowManager.hyprland.enable) {
    services.hyprpaper = {
      enable = true;
      settings = {
        # Hyprpaper defaults splash=true and paints random Hyprland quotes over wallpapers.
        splash = false;
      };
    };

    wayland.windowManager.hyprland.settings.misc.disable_hyprland_logo = true;

    # Chain off hyprpaper, not graphical-session.target: HM's hyprpaper unit is
    # `After=graphical-session.target`, so also `WantedBy`/`PartOf` that target here
    # creates an ordering cycle and systemd drops rwpspread on login (blank wallpaper).
    systemd.user.services.rwpspread = {
      Unit = {
        Description = "rwpspread multi-monitor wallpaper (Hyprpaper backend)";
        After = ["hyprpaper.service"];
        Requires = ["hyprpaper.service"];
        PartOf = ["hyprpaper.service"];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };

      Install.WantedBy = ["hyprpaper.service"];

      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${outDir}";
        ExecStart = lib.escapeShellArgs [
          (lib.getExe pkgs.rwpspread)
          "-d"
          "-b"
          "hyprpaper"
          "-i"
          "${wallpaper}"
          "-o"
          outDir
        ];
        Restart = "on-failure";
        RestartSec = "3";
        # rwpspread shells out to `pidof` to locate hyprpaper — include procps on the PATH.
        Environment = [
          "PATH=${lib.makeBinPath [pkgs.procps pkgs.hyprland pkgs.hyprpaper]}"
        ];
      };
    };
  }

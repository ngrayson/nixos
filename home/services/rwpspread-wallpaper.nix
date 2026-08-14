# Tawa: span `izar-utopia.png` across monitors via rwpspread (`-b hyprpaper`). Stylix Hyprpaper is off —
# see `home/stylix.nix` (`hyprpaper.enable = false` when `hostIsTawa`).
{
  config,
  lib,
  nixosConfig ? null,
  pkgs,
  ...
}: let
  hostIsTawa = nixosConfig != null && nixosConfig.networking.hostName == "Tawa";
  wallpaper = builtins.path {
    path = ../../izar-utopia.png;
    name = "izar-utopia.png";
  };
  outDir = "${config.home.homeDirectory}/.cache/rwpspread";
in
  lib.mkIf (hostIsTawa && config.wayland.windowManager.hyprland.enable) {
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

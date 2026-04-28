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
      settings = {};
    };

    wayland.windowManager.hyprland.settings.misc.disable_hyprland_logo = true;

    systemd.user.services.rwpspread = {
      Unit = {
        Description = "rwpspread multi-monitor wallpaper (Hyprpaper backend)";
        After = ["hyprpaper.service"];
        PartOf = [config.wayland.systemd.target];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };

      Install.WantedBy = [config.wayland.systemd.target];

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
        Environment = [
          "PATH=${lib.makeBinPath [pkgs.hyprland pkgs.hyprpaper]}"
        ];
      };
    };
  }

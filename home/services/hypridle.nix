# Idle lock (Quickshell) + DPMS (see `hypr/scripts.nix`).
{
  lib,
  config,
  pkgs,
  ...
}: let
  hs = import ../hypr/scripts.nix {inherit config lib pkgs;};
in {
  services.hypridle = {
    enable = true;
    package = pkgs.hypridle;
    settings = let
      lock = lib.getExe hs.quickshellLock;
      dpmsOff = lib.getExe hs.hyprDpmsAllOff;
      dpmsOn = lib.getExe hs.hyprDpmsAllOn;
    in {
      general = {
        lock_cmd = lock;
        before_sleep_cmd = lock;
        after_sleep_cmd = dpmsOn;
        ignore_dbus_inhibit = false;
      };
      listener = [
        {
          timeout = 300;
          on-timeout = lock;
        }
        {
          timeout = 600;
          on-timeout = dpmsOff;
          on-resume = dpmsOn;
        }
      ];
    };
  };
}

# Idle lock (Quickshell) + DPMS (see `hypr/scripts.nix`).
{
  lib,
  config,
  pkgs,
  nixosConfig ? null,
  ...
}: let
  hs = import ../hypr/scripts.nix {inherit config lib pkgs;};
  hostName =
    if nixosConfig == null
    then ""
    else nixosConfig.networking.hostName;
in {
  services.hypridle = {
    enable = true;
    package = pkgs.hypridle;
    settings = let
      lock = lib.getExe hs.quickshellLockGuarded;
      beforeSleep = lib.getExe hs.hyprBeforeSleep;
      dpmsOff = lib.getExe hs.hyprDpmsAllOffGuarded;
      dpmsOn = lib.getExe hs.hyprDpmsAllOn;
      # Theseus only: match logind suspend-then-hibernate. Tawa/Hearth stay on suspend.
      suspendGuarded =
        if hostName == "Theseus"
        then lib.getExe hs.hyprSuspendThenHibernateGuarded
        else lib.getExe hs.hyprSuspendGuarded;
    in {
      general = {
        lock_cmd = lock;
        before_sleep_cmd = beforeSleep;
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
        {
          timeout = 1800;
          on-timeout = suspendGuarded;
        }
      ];
    };
  };
}

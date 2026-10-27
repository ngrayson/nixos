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
        # hypridle 0.1.7 rebuilds every idle listener when a D-Bus inhibit drops to 0
        # while idled, losing the "idled" state, so on-resume (dpms on) never fires.
        # Wayland idle-inhibit (browsers, mpv, SDL games) is handled by Hyprland and unaffected.
        ignore_dbus_inhibit = true;
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
          # Theseus laptop: 30m. Tawa desktop: 150m (9000s) so a short step-away
          # is lock+DPMS only — S3 resume is what hangs the lock after password.
          timeout =
            if hostName == "Theseus"
            then 1800
            else 9000;
          on-timeout = suspendGuarded;
        }
      ];
    };
  };
}

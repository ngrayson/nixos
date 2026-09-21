# Polls tailscaled's health on a user timer and writes a flat JSON file the
# Quickshell bar's tailscale pill reads. Same shape as ./claude-usage.nix: the
# script owns the polling, the debounce and the notification; the bar only
# ever reads simplified JSON. The Python lives in ./tailscale-health/poll.py
# as a real file so it can be run against fixtures before any switch.
#
# WHY THIS EXISTS: the wifi pill only knows NetworkManager's link state, so a
# tailscale DNS outage looks exactly like healthy wifi. `tailscale status
# --json` (local unix socket, works unprivileged, ~20 ms) reports the
# daemon's own warnables, and that is the signal worth surfacing.
#
# DEBOUNCE: warming-up and no-derp-connection flap for a few seconds on every
# resume. A warning is ACTIVE only after two consecutive polls >= 15 s apart;
# only active warnings reach the pill and the notification. One critical
# notification per episode, replaced by a short "healthy again" via a dunst
# stack tag on recovery. A non-Running backend shows on the pill but never
# notifies.
#
# TEST HOOKS (the unit sets none): QS_TS_OUT overrides the state path,
# QS_TS_STATUS_FILE feeds a JSON fixture instead of the CLI, QS_TS_NOTIFY
# replaces notify-send (`true` to silence it). Never test by breaking the
# network, sleeping the machine, or restarting tailscaled.
#
# PERSONAL DATA: the state file carries only BackendState and the Health
# message strings. Never write Self, Peer, CurrentTailnet, MagicDNSSuffix or
# TailscaleIPs -- the tailnet name and addresses are personal, and the file
# is readable to anything running as this user.
{
  lib,
  pkgs,
  ...
}: let
  # Ten seconds keeps "within ~20 s" honest with the 15 s debounce on top.
  intervalSec = 10;

  tailscaleHealth = pkgs.writeShellApplication {
    name = "qs-tailscale-health";
    runtimeInputs = [pkgs.coreutils pkgs.python3 pkgs.tailscale pkgs.libnotify];
    text = ''
      set -euo pipefail

      # Resolve the default here and hand the resolved value to Python, as
      # claude-usage.nix does -- exporting a raw unset QS_TS_OUT would skip it.
      QS_TS_OUT="''${QS_TS_OUT:-''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/tailscale-health/state.json}"
      mkdir -p "$(dirname "$QS_TS_OUT")"
      export QS_TS_OUT

      exec python3 ${./tailscale-health/poll.py}
    '';
  };
in {
  home.packages = [tailscaleHealth];

  systemd.user.services.qs-tailscale-health = {
    Unit = {
      Description = "Poll tailscaled health for the Quickshell bar pill";
      # Needs a notification daemon to deliver to.
      After = ["dunst.service"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe tailscaleHealth;
    };
  };

  systemd.user.timers.qs-tailscale-health = {
    Unit.Description = "Refresh tailscaled health for the Quickshell bar";
    Timer = {
      OnStartupSec = "15s";
      OnUnitActiveSec = "${toString intervalSec}s";
      # The user manager's default AccuracySec is 1 min, which would coalesce
      # a 10 s timer into once a minute. Every other timer here polls at
      # >= 60 s, so this is the first one that has to say so.
      AccuracySec = "1s";
    };
    Install.WantedBy = ["timers.target"];
  };
}

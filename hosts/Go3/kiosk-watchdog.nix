# Restarts the kiosk when the dashboard PAGE has died but everything around it
# is healthy.
#
# This exists because of 2026-09-07: Go3 booted at 03:30, Chromium came up, the
# page loaded its bundle -- and then stopped executing. `systemctl --failed`
# was empty, cage-tty1 was active, all ten Chromium processes were alive, the
# panel and backlight were behaving, and the wall showed a uniform background
# colour for ten hours until someone restarted cage by hand. Nothing on the box
# knew anything was wrong, because from the outside nothing was.
#
# The signal has to come from the page itself. KioskStats in the dashboard
# polls the local stats server every 5s and does so unconditionally -- it never
# checks document.hidden, only usePanelWokeAt does -- so silence on that
# endpoint is unambiguous: the page is not running. The stats server records
# the last request; /health reports the gap without touching it.
#
# Deliberately independent of the page's cooperation: an error boundary inside
# the dashboard can only recover a React tree that still has a running event
# loop. This layer recovers a renderer that has stopped entirely.
{
  lib,
  pkgs,
  ...
}: let
  # How long the page may be silent before it is considered dead. KioskStats
  # polls every 5s, so 600s is 120 missed polls -- far outside anything a slow
  # network or a busy renderer explains.
  maxSilence = 600;
  # How long after cage starts before the watchdog will act at all. A cold boot
  # has to fetch the bundle from Hearth over Wi-Fi before the first poll can
  # happen; restarting during that window would fight the boot it is meant to
  # protect.
  grace = 600;

  go3-kiosk-watchdog = pkgs.writeShellApplication {
    name = "go3-kiosk-watchdog";
    runtimeInputs = [pkgs.curl pkgs.jq pkgs.systemd pkgs.coreutils];
    text = ''
      set -euo pipefail

      MAX_SILENCE="''${GO3_WATCHDOG_MAX_SILENCE:-${toString maxSilence}}"
      GRACE="''${GO3_WATCHDOG_GRACE:-${toString grace}}"

      # A stats server that is down is not the page's fault, and restarting the
      # kiosk would not fix it. Exit quietly; Restart=always brings it back.
      if ! health="$(curl -fsS --max-time 5 http://127.0.0.1:18090/health 2>/dev/null)"; then
        exit 0
      fi

      silence="$(printf '%s' "$health" | jq -r '.seconds_since_stats_request // "null"')"

      # Only act once cage has been up long enough for a healthy page to have
      # polled at least once. ActiveEnterTimestampMonotonic is in microseconds
      # and is 0 when the unit is not running.
      cage_us="$(systemctl show cage-tty1 -p ActiveEnterTimestampMonotonic --value)"
      if [ -z "$cage_us" ] || [ "$cage_us" = "0" ]; then
        exit 0
      fi
      now_us="$(cut -d' ' -f1 /proc/uptime | tr -d '.' | sed 's/$/0000/')"
      cage_uptime=$(( (now_us - cage_us) / 1000000 ))
      if [ "$cage_uptime" -lt "$GRACE" ]; then
        exit 0
      fi

      # null means the page has NEVER polled since the stats server started --
      # a page that died during its first load, which is exactly the 2026-09-07
      # failure.
      if [ "$silence" = "null" ]; then
        echo "go3-kiosk-watchdog: dashboard has never polled (cage up ''${cage_uptime}s); restarting cage-tty1"
        systemctl restart cage-tty1
        exit 0
      fi

      if [ "''${silence%.*}" -gt "$MAX_SILENCE" ]; then
        echo "go3-kiosk-watchdog: no dashboard poll for ''${silence}s; restarting cage-tty1"
        systemctl restart cage-tty1
      fi
    '';
  };
in {
  systemd.services.go3-kiosk-watchdog = {
    description = "Restart the Go3 kiosk when the dashboard page has stopped polling";
    # Not bound to cage-tty1's lifecycle, for the reason idle-blank.nix
    # documents at length: giving this unit a wantedBy on cage-tty1 would put a
    # symlink in cage-tty1.service.wants/, so editing this file would change
    # cage's dependencies and a switch would restart the kiosk. The timer is
    # what keeps this running.
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe go3-kiosk-watchdog;
      # Needs root to restart cage-tty1; everything else is loopback + /proc.
      ProtectHome = true;
      PrivateTmp = true;
      RestrictAddressFamilies = ["AF_INET" "AF_UNIX"];
      IPAddressAllow = ["localhost"];
      IPAddressDeny = ["any"];
    };
  };

  systemd.timers.go3-kiosk-watchdog = {
    description = "Check every minute that the Go3 dashboard page is still alive";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1min";
      AccuracySec = "10s";
    };
  };
}

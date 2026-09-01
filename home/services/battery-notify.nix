# Critical, non-expiring notification when a laptop battery gets low.
#
# The persistence requirement is already met: home/services/dunst.nix styles
# urgency_critical with timeout = 0, so a critical notification stays until it
# is dismissed. This only has to fire one.
#
# Battery presence is detected at runtime, never by hostname, so a future
# laptop needs no repo change -- and a desktop no-ops cleanly.
{
  config,
  lib,
  pkgs,
  ...
}: let
  thresholdPct = 10;
  # Rearm above this rather than at the threshold, so a battery hovering on the
  # line cannot re-fire an un-dismissable notification every poll.
  rearmPct = 15;
  intervalSec = 60;

  battery-notify = pkgs.writeShellApplication {
    name = "battery-notify";
    runtimeInputs = [pkgs.coreutils pkgs.libnotify];
    text = ''
      set -euo pipefail

      THRESHOLD=${toString thresholdPct}
      REARM=${toString rearmPct}
      STATE="''${XDG_CACHE_HOME:-$HOME/.cache}/battery-notify.fired"
      # Overridable so the threshold and hysteresis logic can be exercised
      # against a scratch tree; the unit sets neither and reads real sysfs.
      SUPPLY_ROOT="''${BATTERY_NOTIFY_SUPPLY_ROOT:-/sys/class/power_supply}"

      # A system battery is type=Battery with scope System. The scope check is
      # the whole point: `upower -e` and a bare type=Battery test both match
      # peripherals -- on Tawa, a desktop, that is a Logitech mouse reporting
      # `scope=Device` and `power supply: no`. Alerting on a mouse at 9% would
      # be worse than not alerting at all. Absent scope means System.
      find_system_battery() {
        local dir scope
        for dir in "$SUPPLY_ROOT"/*; do
          [[ -r "$dir/type" ]] || continue
          [[ "$(cat "$dir/type")" == "Battery" ]] || continue
          scope="System"
          [[ -r "$dir/scope" ]] && scope="$(cat "$dir/scope")"
          [[ "$scope" == "System" ]] || continue
          [[ -r "$dir/capacity" && -r "$dir/status" ]] || continue
          printf '%s\n' "$dir"
          return 0
        done
        return 1
      }

      bat="$(find_system_battery || true)"
      if [[ -z "$bat" ]]; then
        # No system battery: a desktop. Nothing to watch, and not an error.
        exit 0
      fi

      pct="$(cat "$bat/capacity")"
      status="$(cat "$bat/status")"

      # Rearm on charge or on recovering past the hysteresis margin, so the
      # next genuine discharge cycle notifies again.
      if [[ "$status" != "Discharging" ]] || [[ "$pct" -ge "$REARM" ]]; then
        rm -f "$STATE"
        exit 0
      fi

      if [[ "$pct" -ge "$THRESHOLD" ]]; then
        exit 0
      fi
      # Already told them about this discharge cycle.
      if [[ -e "$STATE" ]]; then
        exit 0
      fi

      # urgency_critical in dunst.nix is timeout = 0, so this stays put.
      notify-send --urgency=critical --app-name=battery \
        "Battery at ''${pct}%" \
        "Plug in $(hostname). Discharging below ''${THRESHOLD}%."
      mkdir -p "$(dirname "$STATE")"
      : >"$STATE"
    '';
  };
in {
  systemd.user.services.battery-notify = {
    Unit = {
      Description = "Warn when a system battery drops below ${toString thresholdPct}%";
      # Needs a notification daemon to deliver to.
      After = ["dunst.service"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe battery-notify;
    };
  };

  systemd.user.timers.battery-notify = {
    Unit.Description = "Battery low-level check";
    Timer = {
      OnStartupSec = "1min";
      OnUnitActiveSec = "${toString intervalSec}s";
      AccuracySec = "10s";
    };
    Install.WantedBy = ["timers.target"];
  };
}

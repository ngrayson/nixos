# Hearthchime alert when Hearth's own battery drops below 25%.
#
# Hearth is a lid-down Surface Laptop 3 on mains, so a discharging battery is
# not a laptop-unplugged problem — it usually means the household lost power.
# That is the signal worth a Discord message.
#
# Fires once per discharge cycle, not once per poll: a state file marks that
# this dip has been reported, and only clears when the battery is charging
# again or has recovered past the rearm margin.
{pkgs, ...}: let
  thresholdPct = 25;
  # Rearm above the threshold rather than at it, so a battery hovering on the
  # line cannot re-fire every poll. Same hysteresis idea as the 10/15 spread in
  # home/services/battery-notify.nix.
  rearmPct = 30;

  hearthchimePost = import ./hearthchime.nix {inherit pkgs;};

  alert = pkgs.writeShellApplication {
    name = "hearth-battery-alert";
    runtimeInputs = [pkgs.coreutils hearthchimePost];
    text = ''
      set -euo pipefail

      THRESHOLD=${toString thresholdPct}
      REARM=${toString rearmPct}
      # Overridable so the threshold and hysteresis logic can be exercised
      # against a scratch tree; the unit sets neither and reads real sysfs.
      SUPPLY_ROOT="''${HEARTH_BATTERY_ALERT_SUPPLY_ROOT:-/sys/class/power_supply}"
      STATE_DIR="''${HEARTH_BATTERY_ALERT_STATE_DIR:-/run/hearth-battery-alert}"
      STATE="$STATE_DIR/fired"

      # A system battery is type=Battery with scope System. The scope check is
      # the whole point, and is lifted from home/services/battery-notify.nix:
      # a bare type=Battery test also matches peripherals — on Tawa, a Logitech
      # mouse reporting scope=Device. Absent scope means System.
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
        # No system battery. Not an error — keeps this module harmless if it
        # is ever imported by a host without one.
        exit 0
      fi

      pct="$(cat "$bat/capacity")"
      status="$(cat "$bat/status")"
      mkdir -p "$STATE_DIR"

      # Rearm on charge or on recovering past the margin, so the next genuine
      # discharge cycle alerts again.
      if [[ "$status" != "Discharging" ]] || [[ "$pct" -ge "$REARM" ]]; then
        rm -f "$STATE"
        exit 0
      fi

      if [[ "$pct" -ge "$THRESHOLD" ]]; then
        exit 0
      fi
      # Already reported this discharge cycle.
      if [[ -e "$STATE" ]]; then
        exit 0
      fi

      msg="Hearth battery at ''${pct}% and discharging below ''${THRESHOLD}%. The house may have lost power."
      if [[ "''${HEARTH_BATTERY_ALERT_DRY_RUN:-}" == "1" ]]; then
        printf '%s\n' "$msg"
      else
        hearth-hearthchime-post "$msg"
      fi
      : >"$STATE"
    '';
  };
in {
  systemd.services.hearth-battery-alert = {
    description = "Hearthchime alert when Hearth's battery drops below ${toString thresholdPct}%";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      # Must be wiz: common/sops.nix gives hearth-discord-webhook owner wiz,
      # mode 0400, and the poster reads it directly.
      User = "wiz";
      Group = "users";
      ExecStart = "${alert}/bin/hearth-battery-alert";
      # ProtectSystem=strict leaves /run read-only, so the state file needs its
      # own runtime directory. Preserve it: a oneshot would otherwise have the
      # directory torn down on every exit, losing the fired marker and posting
      # again on the next poll — the exact thing the marker exists to prevent.
      RuntimeDirectory = "hearth-battery-alert";
      RuntimeDirectoryPreserve = "yes";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      TimeoutStartSec = "60s";
    };
  };

  systemd.timers.hearth-battery-alert = {
    wantedBy = ["timers.target"];
    timerConfig = {
      # Battery state changes slowly; no need for weather-alert's daily cadence
      # or the stats server's 60s polling.
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      AccuracySec = "30s";
      Unit = "hearth-battery-alert.service";
    };
  };
}

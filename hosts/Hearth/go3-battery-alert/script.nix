# The hearth-go3-battery-alert script, split out of ../go3-battery-alert.nix so
# it builds without the Hearth closure: the flake's
# `hearth-go3-battery-alert-tests` check (tests/hearth-go3-battery-alert/run.sh)
# runs this exact package against a scratch state dir.
#
# Not a NixOS module — a function returning a package, like ../hearthchime.nix.
{
  pkgs,
  thresholdPct ? 25,
  rearmPct ? 30,
}: let
  hearthchimePost = import ../hearthchime.nix {inherit pkgs;};
in
  pkgs.writeShellApplication {
    name = "hearth-go3-battery-alert";
    runtimeInputs = [pkgs.coreutils pkgs.gnugrep pkgs.openssh pkgs.tailscale hearthchimePost];
    text = ''
      set -euo pipefail

      THRESHOLD="''${HEARTH_GO3_BATTERY_ALERT_THRESHOLD:-${toString thresholdPct}}"
      REARM="''${HEARTH_GO3_BATTERY_ALERT_REARM:-${toString rearmPct}}"
      KEY="''${HEARTH_GO3_CHECKIN_KEY:-/run/secrets/hearth-go3-checkin}"
      KNOWN_HOSTS="''${HEARTH_GO3_CHECKIN_KNOWN_HOSTS:-/var/lib/hearth-go3-checkin/known_hosts}"
      PEER="''${HEARTH_GO3_CHECKIN_PEER:-go3}"
      # Its own state, separate from battery-alert.nix: Go3's discharge cycle
      # and Hearth's are unrelated. /var/lib, not /run — see the unit.
      STATE_DIR="''${HEARTH_GO3_BATTERY_ALERT_STATE_DIR:-/var/lib/hearth-go3-battery-alert}"
      # Exists while a low alert has posted and no recovery has been reported.
      LOW="$STATE_DIR/low"
      # `<epoch> <pct> <status>` from the latest successful readout.
      LAST="$STATE_DIR/last-readout"
      now="''${HEARTH_GO3_BATTERY_ALERT_NOW:-$(date +%s)}"

      mkdir -p "$STATE_DIR"

      post() {
        if [[ "''${HEARTH_GO3_BATTERY_ALERT_DRY_RUN:-}" == "1" ]]; then
          printf '%s\n' "$1"
        else
          hearth-hearthchime-post "$1"
        fi
      }

      # Test hook: when set (even to empty), it IS the readout and Go3 is never
      # contacted. Empty means "unreachable".
      if [[ -n "''${HEARTH_GO3_BATTERY_ALERT_READOUT+x}" ]]; then
        readout="$HEARTH_GO3_BATTERY_ALERT_READOUT"
      else
        if [[ ! -r "$KEY" ]]; then
          echo "check-in key unreadable; skipping" >&2
          exit 0
        fi

        # Hearth runs tailscale with --accept-dns=false (see remote-access.nix:
        # MagicDNS as the only resolver hung public lookups on this LAN), so
        # go3's MagicDNS name does not resolve here. Ask tailscaled for the
        # peer address instead of hardcoding one — its socket answers queries
        # without root, and this survives the node being re-added.
        addr="$(tailscale ip -4 "$PEER" 2>/dev/null || true)"
        if [[ -z "$addr" ]]; then
          echo "go3 has no tailnet address right now; skipping" >&2
          exit 0
        fi

        # The remote command is irrelevant — Go3's authorized_keys forces its
        # own — but passing one avoids requesting a PTY. BatchMode so this can
        # never block an unattended timer on a prompt.
        readout="$(ssh -F /dev/null -i "$KEY" \
          -o IdentitiesOnly=yes \
          -o BatchMode=yes \
          -o StrictHostKeyChecking=accept-new \
          -o UserKnownHostsFile="$KNOWN_HOSTS" \
          -o ConnectTimeout=10 \
          -l wiz "$addr" true 2>/dev/null || true)"
      fi

      if [[ -z "$readout" ]]; then
        # Asleep, off the network, or the public key is not on Go3 yet. Not a
        # battery event: hold whatever state we are in.
        echo "no battery readout from go3; skipping" >&2
        exit 0
      fi

      # First space, not last: "50 Not charging" must give "Not charging".
      pct="''${readout%% *}"
      status="''${readout#* }"
      if [[ ! "$pct" =~ ^[0-9]+$ ]]; then
        echo "unexpected readout from go3; skipping" >&2
        exit 0
      fi
      printf '%s %s %s\n' "$now" "$pct" "$status" >"$LAST"

      case "$status" in
        Charging | Full | "Not charging") plugged=1 ;;
        Discharging) plugged=0 ;;
        *)
          echo "go3 battery status '$status'; holding state" >&2
          exit 0
          ;;
      esac

      if [[ -e "$LOW" ]]; then
        if (( plugged )); then
          low_pct="$(grep '^pct=' "$LOW" | cut -d= -f2 || true)"
          since="$(grep '^since=' "$LOW" | cut -d= -f2 || true)"
          if [[ "$since" =~ ^[0-9]+$ ]] && (( now >= since )); then
            mins=$(( (now - since) / 60 ))
            if (( mins >= 60 )); then
              ago="$(( mins / 60 ))h $(( mins % 60 ))m ago"
            else
              ago="''${mins}m ago"
            fi
          else
            ago="earlier"
          fi
          # A hand-made or truncated file degrades the wording, never the post.
          if [[ "$low_pct" =~ ^[0-9]+$ ]]; then
            was="Was ''${low_pct}% $ago"
          else
            was="Was low $ago"
          fi
          # "Not charging" / "Full" are plugged in but held by the firmware's
          # charge cap, so only "Charging" gets to say it is charging.
          if [[ "$status" == "Charging" ]]; then
            head="Go3 kiosk is charging again: ''${pct}%."
          else
            head="Go3 kiosk is plugged in again: ''${pct}% (''${status})."
          fi
          post "$head $was — power looks restored."
          rm -f "$LOW"
        elif (( pct >= REARM )); then
          # A battery cannot climb while discharging: readout noise, not a
          # recovery, so rearm without claiming one.
          rm -f "$LOW"
        fi
        exit 0
      fi

      if (( ! plugged )) && (( pct < THRESHOLD )); then
        post "Go3 kiosk battery at ''${pct}% and discharging below ''${THRESHOLD}%. The house may have lost power."
        # Latch even if the post failed (the poster fails open): a flapping
        # webhook must not turn into one message per tick.
        printf 'pct=%s\nsince=%s\n' "$pct" "$now" >"$LOW"
      fi
    '';
  }

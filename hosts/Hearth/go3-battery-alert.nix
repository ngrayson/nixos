# Hearthchime alert when the Go3 wall kiosk's battery drops below 25%.
#
# Companion to battery-alert.nix, which watches Hearth's own battery. Both
# matter for the same reason — a discharging battery on a mains-powered
# appliance usually means the house lost power — but this one is the awkward
# half, because Go3 must hold no secrets.
#
# So Hearth does the reaching: it SSHes into Go3 with a key pinned to a forced
# command (hosts/Go3/battery-checkin.nix), reads two numbers, and does the
# alerting itself with the webhook it already has.
#
# Fails open on every reachability problem. A kiosk that is asleep, off the
# Wi-Fi, or not yet provisioned must never produce an alert — only a confirmed
# low reading does. "Cannot reach Go3" is not a battery event.
#
# Inert until Nick provisions the keypair: without secrets/hearth-go3-checkin.yaml
# this module defines nothing at all, so Hearth still evaluates and builds.
{
  lib,
  pkgs,
  ...
}: let
  thresholdPct = 25;
  rearmPct = 30;

  keySecret = ../../secrets/hearth-go3-checkin.yaml;
  haveKey = builtins.pathExists keySecret;

  hearthchimePost = import ./hearthchime.nix {inherit pkgs;};

  alert = pkgs.writeShellApplication {
    name = "hearth-go3-battery-alert";
    runtimeInputs = [pkgs.coreutils pkgs.openssh pkgs.tailscale hearthchimePost];
    text = ''
      set -euo pipefail

      THRESHOLD=${toString thresholdPct}
      REARM=${toString rearmPct}
      KEY="''${HEARTH_GO3_CHECKIN_KEY:-/run/secrets/hearth-go3-checkin}"
      KNOWN_HOSTS="''${HEARTH_GO3_CHECKIN_KNOWN_HOSTS:-/var/lib/hearth-go3-checkin/known_hosts}"
      PEER="''${HEARTH_GO3_CHECKIN_PEER:-go3}"
      # Its own state file: Go3's discharge cycle and Hearth's are unrelated
      # and must not share a fired marker.
      STATE_DIR="''${HEARTH_GO3_BATTERY_ALERT_STATE_DIR:-/run/hearth-go3-battery-alert}"
      STATE="$STATE_DIR/fired"

      mkdir -p "$STATE_DIR"

      if [[ ! -r "$KEY" ]]; then
        echo "check-in key unreadable; skipping" >&2
        exit 0
      fi

      # Hearth runs tailscale with --accept-dns=false (see remote-access.nix:
      # MagicDNS as the only resolver hung public lookups on this LAN), so
      # go3.tail6cd822.ts.net does not resolve here. Ask tailscaled for the
      # peer address instead of hardcoding one — its socket answers queries
      # without root, and this survives the node being re-added.
      addr="$(tailscale ip -4 "$PEER" 2>/dev/null || true)"
      if [[ -z "$addr" ]]; then
        echo "go3 has no tailnet address right now; skipping" >&2
        exit 0
      fi

      # The remote command is irrelevant — Go3's authorized_keys forces its own
      # — but passing one avoids requesting a PTY. BatchMode so this can never
      # block an unattended timer on a prompt.
      readout="$(ssh -F /dev/null -i "$KEY" \
        -o IdentitiesOnly=yes \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$KNOWN_HOSTS" \
        -o ConnectTimeout=10 \
        -l wiz "$addr" true 2>/dev/null || true)"

      if [[ -z "$readout" ]]; then
        # Asleep, off the network, or the public key is not on Go3 yet.
        echo "no battery readout from go3; skipping" >&2
        exit 0
      fi

      pct="''${readout%% *}"
      status="''${readout##* }"
      if [[ ! "$pct" =~ ^[0-9]+$ ]]; then
        echo "unexpected readout from go3; skipping" >&2
        exit 0
      fi

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

      msg="Go3 kiosk battery at ''${pct}% and discharging below ''${THRESHOLD}%. The house may have lost power."
      if [[ "''${HEARTH_GO3_BATTERY_ALERT_DRY_RUN:-}" == "1" ]]; then
        printf '%s\n' "$msg"
      else
        hearth-hearthchime-post "$msg"
      fi
      : >"$STATE"
    '';
  };
in
  lib.mkIf haveKey {
    sops.secrets.hearth-go3-checkin = {
      sopsFile = keySecret;
      key = "private_key";
      owner = "wiz";
      group = "users";
      mode = "0400";
    };

    systemd.services.hearth-go3-battery-alert = {
      description = "Hearthchime alert when Go3's battery drops below ${toString thresholdPct}%";
      after = ["network-online.target" "tailscaled.service"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        # wiz owns both the webhook secret and the check-in key.
        User = "wiz";
        Group = "users";
        ExecStart = "${alert}/bin/hearth-go3-battery-alert";
        # known_hosts needs somewhere durable; ProtectHome hides the real one,
        # so give ssh a HOME it can actually use.
        StateDirectory = "hearth-go3-checkin";
        Environment = ["HOME=/var/lib/hearth-go3-checkin"];
        # As in battery-alert.nix: /run is read-only under ProtectSystem=strict,
        # and a oneshot would lose the fired marker on every exit without
        # RuntimeDirectoryPreserve — re-posting on the next poll.
        RuntimeDirectory = "hearth-go3-battery-alert";
        RuntimeDirectoryPreserve = "yes";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        TimeoutStartSec = "90s";
      };
    };

    systemd.timers.hearth-go3-battery-alert = {
      wantedBy = ["timers.target"];
      timerConfig = {
        # Coarser than Hearth's own 5min: this one crosses the network, and
        # should not wake the kiosk's radio more often than it needs to. An SSH
        # login is not input, so it never disturbs idle-blank's dim state.
        OnBootSec = "3min";
        OnUnitActiveSec = "10min";
        AccuracySec = "30s";
        Unit = "hearth-go3-battery-alert.service";
      };
    };
  }

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
# Once per episode: after the low alert posts, the first tick that finds Go3
# plugged in again (Charging, Full or Not charging) posts one follow-up —
# "charging again" / "plugged in again", with how low it got and how long ago
# — then re-arms. Unreachable and Unknown ticks hold the state either way.
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

  # The script lives in its own file so the flake's
  # hearth-go3-battery-alert-tests check can build and drive it without the
  # Hearth closure.
  alert = import ./go3-battery-alert/script.nix {inherit pkgs thresholdPct rearmPct;};
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
        # The second directory holds the low-alert latch and last-readout. It
        # is /var/lib, not /run, because a house power loss — the event this
        # alert reports — can reboot Hearth too, and a /run latch would then
        # either re-post the low alert or never post the follow-up.
        StateDirectory = ["hearth-go3-checkin" "hearth-go3-battery-alert"];
        Environment = ["HOME=/var/lib/hearth-go3-checkin"];
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

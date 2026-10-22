# Fetch private ICS feeds on Hearth and merge them into one calendar.ics.
# The browser only reads /calendar.ics; the URLs never leave this host and are
# never logged (a Google secret address is read access to the whole calendar).
#
# The feed list is a sops secret (secrets/hearth-calendar-feeds.yaml, key
# `feeds`, a JSON list of {name, url, calendarId}) read at run time. It must
# never be interpolated into the build: anything in /nix/store is readable by
# every account on Hearth and on the builder. Edit it with
# `sops secrets/hearth-calendar-feeds.yaml`; until that file exists the card
# shows no events.
{
  config,
  lib,
  pkgs,
  ...
}: let
  feedsFile = ../../secrets/hearth-calendar-feeds.yaml;
  haveFeeds = builtins.pathExists feedsFile;
  writer = pkgs.writeShellApplication {
    name = "hearth-intranet-calendar";
    runtimeInputs = [pkgs.coreutils pkgs.python3];
    text = ''
      set -euo pipefail
      mkdir -p /run/hearth-intranet
      python3 ${./intranet-calendar-merge.py}
    '';
  };
in {
  sops.secrets.hearth-calendar-feeds = lib.mkIf haveFeeds {
    sopsFile = feedsFile;
    key = "feeds";
    owner = "hearth-intranet";
    group = "hearth-intranet";
    mode = "0400";
  };

  systemd.services.hearth-intranet-calendar = {
    description = "Fetch Hearth intranet calendar.ics";
    after = ["network-online.target" "sops-install-secrets.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "hearth-intranet";
      Group = "hearth-intranet";
      ExecStart = "${writer}/bin/hearth-intranet-calendar";
      Environment = lib.optionals haveFeeds [
        "HEARTH_CALENDAR_FEEDS_FILE=${config.sops.secrets.hearth-calendar-feeds.path}"
      ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = ["/run/hearth-intranet"];
      TimeoutStartSec = "120s";
    };
  };

  systemd.timers.hearth-intranet-calendar = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "15min";
      AccuracySec = "30s";
      Unit = "hearth-intranet-calendar.service";
    };
  };
}

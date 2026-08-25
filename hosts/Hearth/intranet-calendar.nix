# Fetch a private ICS on Hearth. The browser only reads /calendar.ics.
{pkgs, ...}: let
  icsUrl = (import ./intranet/config).calendar.calendarIcsUrl or null;
  urlText = if icsUrl == null || icsUrl == "" then "" else toString icsUrl;
  writer = pkgs.writeShellApplication {
    name = "hearth-intranet-calendar";
    runtimeInputs = [pkgs.coreutils pkgs.curl];
    text = ''
      set -euo pipefail
      url=${pkgs.lib.escapeShellArg urlText}
      out=/run/hearth-intranet/calendar.ics
      if [[ -z "$url" ]]; then
        rm -f "$out"
        exit 0
      fi
      tmp="$out.tmp"
      if curl -fsS --max-time 20 -o "$tmp" "$url"; then
        chmod 0644 "$tmp"
        mv "$tmp" "$out"
      else
        rm -f "$tmp"
        exit 0
      fi
    '';
  };
in {
  systemd.services.hearth-intranet-calendar = {
    description = "Fetch Hearth intranet calendar.ics";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "hearth-intranet";
      Group = "hearth-intranet";
      ExecStart = "${writer}/bin/hearth-intranet-calendar";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = ["/run/hearth-intranet"];
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

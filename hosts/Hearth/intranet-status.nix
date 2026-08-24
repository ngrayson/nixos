# Oneshot + timer: write /run/hearth-intranet/status.json for home.wizt.org.
# Probe facts match scripts/hearth-healthcheck.sh (COLD UUID default).
{
  pkgs,
  ...
}: let
  coldUuid = "22C21140C2111A1D";
  writer = pkgs.writeShellApplication {
    name = "hearth-intranet-status";
    runtimeInputs = [pkgs.coreutils pkgs.util-linux pkgs.python3];
    text = ''
      set -euo pipefail
      mkdir -p /run/hearth-intranet
      python3 - ${coldUuid} <<'PY'
      import json, os, subprocess, sys, time

      cold_uuid = sys.argv[1]
      out = "/run/hearth-intranet/status.json"


      def df_path(path):
          line = subprocess.check_output(["df", "-hP", path], text=True).splitlines()[1].split()
          return {"usedPercent": int(line[4].rstrip("%")), "avail": line[3]}


      root = df_path("/")
      cold = {"mounted": False, "uuidMatch": False}
      if os.path.ismount("/mnt/cold"):
          uuid = subprocess.check_output(
              ["findmnt", "-n", "-o", "UUID", "/mnt/cold"], text=True
          ).strip()
          src = subprocess.check_output(
              ["findmnt", "-n", "-o", "SOURCE", "/mnt/cold"], text=True
          ).strip()
          match = uuid == cold_uuid or cold_uuid in src
          cold = {"mounted": True, "uuidMatch": match, **df_path("/mnt/cold")}

      battery = None
      for name in sorted(os.listdir("/sys/class/power_supply")) if os.path.isdir("/sys/class/power_supply") else []:
          base = f"/sys/class/power_supply/{name}"
          typ_path = os.path.join(base, "type")
          cap_path = os.path.join(base, "capacity")
          if not os.path.isfile(typ_path) or not os.path.isfile(cap_path):
              continue
          typ = open(typ_path, encoding="utf-8").read().strip()
          if typ != "Battery":
              continue
          status_path = os.path.join(base, "status")
          status = "unknown"
          if os.path.isfile(status_path):
              status = open(status_path, encoding="utf-8").read().strip().lower()
          battery = {
              "percent": int(open(cap_path, encoding="utf-8").read().strip()),
              "status": status,
          }
          break

      payload = {
          "root": root,
          "cold": cold,
          "battery": battery,
          "pihole": {"enabled": False},
          "generatedAt": int(time.time()),
      }
      tmp = out + ".tmp"
      with open(tmp, "w", encoding="utf-8") as fh:
          json.dump(payload, fh)
          fh.write("\n")
      os.chmod(tmp, 0o644)
      os.replace(tmp, out)
      PY
    '';
  };
in {
  systemd.services.hearth-intranet-status = {
    description = "Write Hearth intranet status.json";
    after = ["local-fs.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "hearth-intranet";
      Group = "hearth-intranet";
      ExecStart = "${writer}/bin/hearth-intranet-status";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = ["/run/hearth-intranet"];
      RestrictAddressFamilies = ["AF_UNIX"];
    };
  };

  systemd.timers.hearth-intranet-status = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "15s";
      OnUnitActiveSec = "60s";
      AccuracySec = "5s";
      Unit = "hearth-intranet-status.service";
    };
  };
}

# Oneshot + timer: write /run/hearth-intranet/status.json for home.wizt.org.
# Probe facts match scripts/hearth-healthcheck.sh (COLD UUID default).
{pkgs, ...}: let
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


      def read_text(path):
          try:
              with open(path, encoding="utf-8") as fh:
                  return fh.read().strip()
          except OSError:
              return None


      def cpu_times():
          with open("/proc/stat", encoding="utf-8") as fh:
              parts = fh.readline().split()
          vals = [int(v) for v in parts[1:]]
          idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
          return sum(vals), idle


      def cpu_usage():
          # A single /proc/stat read is cumulative since boot, so sample twice.
          try:
              total0, idle0 = cpu_times()
              time.sleep(0.5)
              total1, idle1 = cpu_times()
          except (OSError, ValueError, IndexError):
              return None
          dt = total1 - total0
          if dt <= 0:
              return None
          return max(0, min(100, round(100.0 * (dt - (idle1 - idle0)) / dt)))


      def load1():
          try:
              return round(os.getloadavg()[0], 2)
          except OSError:
              return None


      def memory():
          info = {}
          try:
              with open("/proc/meminfo", encoding="utf-8") as fh:
                  for line in fh:
                      key, _, rest = line.partition(":")
                      info[key] = int(rest.split()[0])
          except (OSError, ValueError, IndexError):
              return None
          total = info.get("MemTotal")
          avail = info.get("MemAvailable")
          if not total or avail is None:
              return None
          used = total - avail
          return {
              "usedPercent": round(100.0 * used / total),
              "usedGiB": round(used / 1048576.0, 1),
              "totalGiB": round(total / 1048576.0, 1),
          }


      def temperature_probe():
          base = "/sys/class/hwmon"
          prefer = ("coretemp", "k10temp", "zenpower")
          best = None
          for entry in sorted(os.listdir(base)) if os.path.isdir(base) else []:
              node = os.path.join(base, entry)
              if read_text(os.path.join(node, "name")) not in prefer:
                  continue
              for fname in sorted(os.listdir(node)):
                  if not (fname.startswith("temp") and fname.endswith("_input")):
                      continue
                  raw = read_text(os.path.join(node, fname))
                  if raw is None or not raw.lstrip("-").isdigit():
                      continue
                  label = read_text(os.path.join(node, fname[: -len("_input")] + "_label")) or ""
                  # "Package id 0" (Intel) / "Tctl" (AMD) is the whole-die number;
                  # per-core sensors rank behind it.
                  rank = 0 if label in ("Package id 0", "Tctl", "Tdie") else 1
                  cand = (rank, round(int(raw) / 1000.0, 1), label or entry)
                  if best is None or cand[0] < best[0]:
                      best = cand
          if best is not None:
              return best
          thermal = "/sys/class/thermal"
          for zone in sorted(os.listdir(thermal)) if os.path.isdir(thermal) else []:
              if not zone.startswith("thermal_zone"):
                  continue
              znode = os.path.join(thermal, zone)
              ztype = read_text(os.path.join(znode, "type"))
              if ztype not in ("x86_pkg_temp", "acpitz"):
                  continue
              raw = read_text(os.path.join(znode, "temp"))
              if raw is None or not raw.lstrip("-").isdigit():
                  continue
              best = (0 if ztype == "x86_pkg_temp" else 1, round(int(raw) / 1000.0, 1), ztype)
              if ztype == "x86_pkg_temp":
                  break
          return best


      def cpu_temperature():
          try:
              best = temperature_probe()
          except OSError:
              return None
          if best is None:
              return None
          return {"celsius": best[1], "sensor": best[2]}


      payload = {
          "root": root,
          "cold": cold,
          "battery": battery,
          "cpu": {"usedPercent": cpu_usage(), "load1": load1(), "cores": os.cpu_count()},
          "memory": memory(),
          "temperature": cpu_temperature(),
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

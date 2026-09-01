# Go3's own CPU, RAM, battery, Wi-Fi and temperature, served to the dashboard
# it displays. A web page has no API for OS-level stats, and home.wizt.org is
# served from Hearth, so the only way the kiosk's own numbers reach the page is
# a local service on this box that the page fetches from loopback.
#
# Hardware facts checked on the machine: Wi-Fi is wlp1s0, the battery is
# /sys/class/power_supply/BAT1, and CPU temperature is the thermal zone whose
# `type` is x86_pkg_temp -- found by type, never by a fixed zone index, since
# zone numbering is not stable across boots.
{pkgs, ...}: let
  port = 18090;

  # One long-lived server rather than the oneshot + timer + JSON file the plan
  # sketched. Same output, but no file on disk, no /run directory, no atomic
  # write, and no wakeups when nobody is asking -- and CPU percentage wants a
  # delta between two samples, which a process that stays alive gets for free
  # by remembering the previous one.
  go3-stats-server =
    pkgs.writers.writePython3Bin "go3-stats-server" {
      libraries = [];
      flakeIgnore = ["E501"];
    } ''
      import glob
      import json
      import os
      import re
      import subprocess
      import time
      from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

      PORT = ${toString port}
      ORIGIN = "https://home.wizt.org"

      _prev_cpu = None


      def cpu_percent():
          """Percentage busy since the previous call; None on the first one."""
          global _prev_cpu
          with open("/proc/stat", encoding="utf-8") as fh:
              parts = [int(v) for v in fh.readline().split()[1:]]
          idle = parts[3] + parts[4]
          total = sum(parts)
          prev, _prev_cpu = _prev_cpu, (idle, total)
          if prev is None:
              return None
          d_idle, d_total = idle - prev[0], total - prev[1]
          if d_total <= 0:
              return None
          return round(100.0 * (1.0 - d_idle / d_total), 1)


      def mem_percent():
          want = {"MemTotal": 0, "MemAvailable": 0}
          with open("/proc/meminfo", encoding="utf-8") as fh:
              for line in fh:
                  key, _, rest = line.partition(":")
                  if key in want:
                      want[key] = int(rest.split()[0])
          if not want["MemTotal"]:
              return None
          return round(100.0 * (1.0 - want["MemAvailable"] / want["MemTotal"]), 1)


      def battery():
          for base in sorted(glob.glob("/sys/class/power_supply/BAT*")):
              try:
                  with open(os.path.join(base, "capacity"), encoding="utf-8") as fh:
                      pct = int(fh.read().strip())
                  with open(os.path.join(base, "status"), encoding="utf-8") as fh:
                      status = fh.read().strip()
                  return pct, status
              except (OSError, ValueError):
                  continue
          return None, None


      def cpu_temp_c():
          # By type, not by index: zone numbering is not stable across boots.
          for zone in sorted(glob.glob("/sys/class/thermal/thermal_zone*")):
              try:
                  with open(os.path.join(zone, "type"), encoding="utf-8") as fh:
                      if fh.read().strip() != "x86_pkg_temp":
                          continue
                  with open(os.path.join(zone, "temp"), encoding="utf-8") as fh:
                      return round(int(fh.read().strip()) / 1000.0, 1)
              except (OSError, ValueError):
                  continue
          return None


      def wifi_signal():
          try:
              out = subprocess.run(
                  ["nmcli", "-t", "-f", "active,signal", "dev", "wifi"],
                  capture_output=True, text=True, timeout=4, check=False,
              ).stdout
          except (OSError, subprocess.SubprocessError):
              return None
          for line in out.splitlines():
              # Already 0-100; the active row is the one we are associated with.
              if line.startswith("yes:"):
                  m = re.match(r"yes:(\d+)", line)
                  if m:
                      return int(m.group(1))
          return None


      def payload():
          pct, status = battery()
          return {
              "cpu_pct": cpu_percent(),
              "mem_pct": mem_percent(),
              "battery_pct": pct,
              "battery_status": status,
              "wifi_signal": wifi_signal(),
              "cpu_temp_c": cpu_temp_c(),
              "generatedAt": int(time.time()),
          }


      class Handler(BaseHTTPRequestHandler):
          def do_GET(self):
              if self.path.split("?")[0] not in ("/", "/stats.json"):
                  self.send_error(404)
                  return
              body = json.dumps(payload()).encode("utf-8")
              self.send_response(200)
              self.send_header("Content-Type", "application/json")
              self.send_header("Content-Length", str(len(body)))
              # The page is same-machine but a different origin, so it needs this.
              self.send_header("Access-Control-Allow-Origin", ORIGIN)
              self.send_header("Cache-Control", "no-store")
              self.end_headers()
              self.wfile.write(body)

          def log_message(self, *_args):
              # A request every 5s forever would be pure journal noise.
              pass


      if __name__ == "__main__":
          # 127.0.0.1 only, never 0.0.0.0: Go3 sits on shared household Wi-Fi and
          # this must not be reachable from it. This is a hard boundary.
          ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    '';
in {
  systemd.services.go3-stats-server = {
    description = "Serve Go3's own system stats to the kiosk dashboard on loopback";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.networkmanager];
    serviceConfig = {
      ExecStart = "${go3-stats-server}/bin/go3-stats-server";
      DynamicUser = true;
      Restart = "always";
      RestartSec = "5s";
      # Nothing here needs to reach the network or write anywhere; it only
      # reads /proc and /sys and answers on loopback.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = ["AF_INET" "AF_UNIX" "AF_NETLINK"];
      IPAddressAllow = ["localhost"];
      IPAddressDeny = ["any"];
    };
  };
}

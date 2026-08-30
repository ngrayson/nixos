# Oneshot + timer: one Hearth poll of AirNow's nearest-monitor observations
# → /run/hearth-intranet/aqi.json. Browsers only read that file.
#
# AirNow reports the AQI measured by real EPA monitoring stations, which is what
# AirNow.gov and most consumer apps show. Open-Meteo's `us_aqi` (what the
# dashboard used before) is a modeled reanalysis value and disagrees with them.
# The API key must never reach the browser, so the poll is server-side and the
# widget reads the static file — same shape as intranet-transit.nix.
{pkgs, ...}: let
  weatherCfg = (import ./intranet/config).weather;
  # AirNow observations update roughly hourly, so a fast poll buys nothing and
  # only burns the hourly request budget. Floor it well above the transit poll.
  pollSeconds = let
    n = weatherCfg.airnowPollSeconds or 600;
  in
    if n < 300
    then 300
    else n;
  pollCfg = pkgs.writeText "hearth-aqi-poll.json" (builtins.toJSON {
    key = weatherCfg.airnowApiKey or "";
    pollSeconds = pollSeconds;
    locations = weatherCfg.locations or [];
  });
  writer = pkgs.writeShellApplication {
    name = "hearth-intranet-aqi";
    runtimeInputs = [pkgs.coreutils pkgs.python3];
    text = ''
      set -euo pipefail
      mkdir -p /run/hearth-intranet
      python3 - ${pollCfg} <<'PY'
      import json, os, sys, time, urllib.error, urllib.parse, urllib.request

      cfg = json.load(open(sys.argv[1], encoding="utf-8"))
      out = "/run/hearth-intranet/aqi.json"
      key = (cfg.get("key") or "").strip()
      poll = max(300, int(cfg.get("pollSeconds") or 600))
      locations = cfg.get("locations") or []

      ENDPOINT = "https://www.airnowapi.org/aq/observation/latLong/current/"
      # Miles. AirNow returns the nearest reporting area within this radius;
      # too small and a location with no nearby monitor reports nothing.
      DISTANCE = "25"


      def log(msg):
          print(msg, file=sys.stderr, flush=True)


      def write(payload):
          tmp = out + ".tmp"
          with open(tmp, "w", encoding="utf-8") as fh:
              json.dump(payload, fh)
              fh.write("\n")
          os.chmod(tmp, 0o644)
          os.replace(tmp, out)


      def blank(index):
          return {"index": index, "aqi": None, "category": None, "ok": False}


      def fetch_location(index, loc):
          """Nearest-monitor AQI for one configured location.

          Fails open per location: any HTTP/parse problem yields a blank entry
          so one unreachable location cannot blank the others.
          """
          if not isinstance(loc, dict):
              return blank(index)
          lat = loc.get("latitude")
          lon = loc.get("longitude")
          if lat is None or lon is None:
              return blank(index)
          url = ENDPOINT + "?" + urllib.parse.urlencode({
              "format": "application/json",
              "latitude": lat,
              "longitude": lon,
              "distance": DISTANCE,
              "API_KEY": key,
          })
          try:
              req = urllib.request.Request(url, headers={"User-Agent": "hearth-intranet-aqi"})
              with urllib.request.urlopen(req, timeout=20) as resp:
                  data = json.load(resp)
          except urllib.error.HTTPError as exc:
              # Never log the URL itself — it carries the API key.
              log(f"location {index}: HTTP {exc.code}")
              return blank(index)
          except Exception as exc:
              log(f"location {index}: {type(exc).__name__}")
              return blank(index)

          if not isinstance(data, list):
              log(f"location {index}: unexpected payload shape")
              return blank(index)

          # AirNow returns one observation per pollutant (typically PM2.5 and
          # Ozone). The headline number is the worst of them, and the category
          # shown is that same dominant pollutant's — this is how AirNow's own
          # site reports it.
          best = None
          for obs in data:
              if not isinstance(obs, dict):
                  continue
              aqi = obs.get("AQI")
              if isinstance(aqi, bool) or not isinstance(aqi, (int, float)):
                  continue
              if aqi < 0:
                  continue
              if best is None or aqi > best.get("AQI"):
                  best = obs

          if best is None:
              log(f"location {index}: no usable AQI in {len(data)} observations")
              return blank(index)

          category = None
          cat = best.get("Category")
          if isinstance(cat, dict):
              name = cat.get("Name")
              if isinstance(name, str) and name:
                  category = name
          return {
              "index": index,
              "aqi": int(best["AQI"]),
              "category": category,
              "ok": True,
          }


      # No key configured yet: write a well-formed empty payload rather than
      # erroring, so a Hearth build without the key still serves the dashboard
      # (the widget renders "ACI —"). Mirrors intranet-calendar.nix's early exit.
      if not key:
          log("airnowApiKey unset; writing empty payload")
          write({"generatedAt": int(time.time()), "pollSeconds": poll, "locations": []})
          sys.exit(0)

      # One entry per configured location, in config order, carrying its own
      # index. The widget renders a filtered subset of locations, so it matches
      # on this index rather than on array position.
      results = [fetch_location(i, loc) for i, loc in enumerate(locations)]
      log(f"{sum(1 for r in results if r['ok'])}/{len(results)} locations ok")

      write({
          "generatedAt": int(time.time()),
          "pollSeconds": poll,
          "locations": results,
      })
      PY
    '';
  };
in {
  systemd.services.hearth-intranet-aqi = {
    description = "Write Hearth intranet aqi.json from AirNow";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "hearth-intranet";
      Group = "hearth-intranet";
      ExecStart = "${writer}/bin/hearth-intranet-aqi";
      TimeoutStartSec = "90s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = ["/run/hearth-intranet"];
    };
  };

  systemd.timers.hearth-intranet-aqi = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "20s";
      OnUnitActiveSec = "${toString pollSeconds}s";
      AccuracySec = "5s";
      Unit = "hearth-intranet-aqi.service";
    };
  };
}

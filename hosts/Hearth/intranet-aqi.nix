# Oneshot + timer: one Hearth poll of AirNow's monitoring stations
# → /run/hearth-intranet/aqi.json. Browsers only read that file.
#
# AirNow reports the AQI measured by real EPA monitoring stations, which is what
# AirNow.gov and most consumer apps show. Open-Meteo's `us_aqi` (what the
# dashboard used before) is a modeled reanalysis value and disagrees with them.
# The API key must never reach the browser, so the poll is server-side and the
# widget reads the static file — same shape as intranet-transit.nix.
#
# This reads `/aq/data/` (individual monitors), NOT
# `/aq/observation/latLong/current/` (a whole *reporting area*). The reporting
# area here — "Seattle-Bellevue-Kent Valley" — spans Everett to Tacoma, so every
# location was showing the worst station in the region: Kirkland and Seattle both
# displayed Kent-S 236th's 53 instead of their own ~29 and ~30.
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
  # How far a monitor may be from a configured location and still speak for it.
  # 25 admits Crystal Mountain's ozone-only sites (Mt Rainier-Jackson at 15.9 mi,
  # Enumclaw Mud Mt at 25.4 mi) while excluding Cle Elum at 30.8 mi, which is on
  # the far side of the Cascade crest and would be the regional-aggregate bug
  # wearing different clothes. Kirkland and Seattle sit far inside it.
  maxStationMiles = let
    n = weatherCfg.airnowMaxStationMiles or 25;
  in
    if n < 1
    then 1
    else n;
  pollCfg = pkgs.writeText "hearth-aqi-poll.json" (builtins.toJSON {
    key = weatherCfg.airnowApiKey or "";
    pollSeconds = pollSeconds;
    maxStationMiles = maxStationMiles;
    locations = weatherCfg.locations or [];
  });
  writer = pkgs.writeShellApplication {
    name = "hearth-intranet-aqi";
    runtimeInputs = [pkgs.coreutils pkgs.python3];
    text = ''
      set -euo pipefail
      mkdir -p /run/hearth-intranet
      python3 - ${pollCfg} <<'PY'
      import json, math, os, sys, time, urllib.error, urllib.parse, urllib.request
      from datetime import datetime, timedelta, timezone

      cfg = json.load(open(sys.argv[1], encoding="utf-8"))
      out = "/run/hearth-intranet/aqi.json"
      key = (cfg.get("key") or "").strip()
      poll = max(300, int(cfg.get("pollSeconds") or 600))
      locations = cfg.get("locations") or []
      max_miles = float(cfg.get("maxStationMiles") or 25)

      ENDPOINT = "https://www.airnowapi.org/aq/data/"
      # One row per parameter per station. PM2.5 and ozone are the ones that
      # normally drive the headline; the rest are carried so the widget's modal
      # can break the figure down by pollutant.
      PARAMETERS = "PM25,OZONE,PM10,CO,NO2,SO2"
      # dataType=B returns AQI *and* concentration; A would be AQI only.
      DATA_TYPE = "B"
      # 0 = permanent monitors only (1 = mobile, 2 = both). Deliberate choice:
      # mobile smoke units are real measurements but they get parked at the fire,
      # so within a 25-mile radius one can report the plume rather than the
      # neighbourhood — a live query returned a unit named "Unit19" at PM2.5 413
      # while every fixed station nearby read under 60. Fixed sites are also
      # stably named, which matters because the payload now shows the site name.
      # The cost is that during a smoke event the closest reading may be excluded.
      MONITOR_TYPE = "0"
      # Observations are hourly and lag; ask for a few hours and keep the most
      # recent row per station per parameter rather than assuming this hour is in.
      WINDOW_HOURS = 4
      EARTH_MILES = 3958.7613
      # AirNow's Category is an integer on this endpoint (it is an object on the
      # reporting-area endpoint). 7 is "Unavailable", which we treat as no name.
      CATEGORY_NAMES = {
          1: "Good",
          2: "Moderate",
          3: "Unhealthy for Sensitive Groups",
          4: "Unhealthy",
          5: "Very Unhealthy",
          6: "Hazardous",
      }


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
          return {"index": index, "aqi": None, "category": None, "ok": False,
                  "pollutants": []}


      def miles_between(lat1, lon1, lat2, lon2):
          """Great-circle distance in miles."""
          p1, p2 = math.radians(lat1), math.radians(lat2)
          dp = p2 - p1
          dl = math.radians(lon2 - lon1)
          a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
          return 2 * EARTH_MILES * math.asin(math.sqrt(a))


      def coords(loc):
          if not isinstance(loc, dict):
              return None
          lat, lon = loc.get("latitude"), loc.get("longitude")
          if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
              return None
          if isinstance(lat, bool) or isinstance(lon, bool):
              return None
          return (float(lat), float(lon))


      def bbox(points):
          """Box enclosing every configured location plus the station radius.

          One request covers all locations — AirNow enforces an hourly request
          budget, and assigning stations locally is cheaper than N calls.
          """
          lats = [p[0] for p in points]
          lons = [p[1] for p in points]
          lat_pad = max_miles / 69.0
          # A degree of longitude shrinks with latitude; pad using the widest
          # (equator-most) edge of the box so the margin is never short.
          widest = min(abs(min(lats)), abs(max(lats)))
          lon_pad = max_miles / max(1.0, 69.0 * math.cos(math.radians(widest)))
          return "%.4f,%.4f,%.4f,%.4f" % (
              min(lons) - lon_pad, min(lats) - lat_pad,
              max(lons) + lon_pad, max(lats) + lat_pad,
          )


      def fetch_rows(points):
          """Every monitor row in the box over the window, or None on failure."""
          now = datetime.now(timezone.utc)
          params = {
              "startDate": (now - timedelta(hours=WINDOW_HOURS)).strftime("%Y-%m-%dT%H"),
              "endDate": now.strftime("%Y-%m-%dT%H"),
              "parameters": PARAMETERS,
              "BBOX": bbox(points),
              "dataType": DATA_TYPE,
              "format": "application/json",
              "verbose": "1",
              "monitorType": MONITOR_TYPE,
              "API_KEY": key,
          }
          url = ENDPOINT + "?" + urllib.parse.urlencode(params)
          # Two attempts: a single transient 5xx would otherwise blank every
          # location at once, where the old per-location poll only blanked one.
          for attempt in (1, 2):
              try:
                  req = urllib.request.Request(
                      url, headers={"User-Agent": "hearth-intranet-aqi"})
                  with urllib.request.urlopen(req, timeout=30) as resp:
                      data = json.load(resp)
              except urllib.error.HTTPError as exc:
                  # Never log the URL itself — it carries the API key.
                  log(f"airnow: HTTP {exc.code} (attempt {attempt})")
              except Exception as exc:
                  log(f"airnow: {type(exc).__name__} (attempt {attempt})")
              else:
                  if isinstance(data, list):
                      return data
                  log("airnow: unexpected payload shape")
                  return None
              if attempt == 1:
                  time.sleep(3)
          return None


      def latest_by_station(rows):
          """Most recent usable row per (site, parameter).

          Drops any row whose AQI is negative: -999 is AirNow's missing-data
          sentinel and CO reports it at several Seattle sites. The headline
          figure is a max across pollutants, so a sentinel would otherwise sail
          straight through the comparison unnoticed.
          """
          best = {}
          for row in rows:
              if not isinstance(row, dict):
                  continue
              site = row.get("SiteName")
              param = row.get("Parameter")
              aqi = row.get("AQI")
              lat, lon = row.get("Latitude"), row.get("Longitude")
              if not isinstance(site, str) or not isinstance(param, str):
                  continue
              if isinstance(aqi, bool) or not isinstance(aqi, (int, float)):
                  continue
              if aqi < 0:
                  continue
              if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
                  continue
              stamp = row.get("UTC") or ""
              seen = best.get((site, param))
              # UTC is "YYYY-MM-DDTHH:MM", so a string compare orders correctly.
              if seen is None or stamp > (seen.get("UTC") or ""):
                  best[(site, param)] = row
          return list(best.values())


      def site_name(row):
          """AirNow ships names with doubled spaces ("Mt Rainier- Jackson  Visitor
          Ctr"). These are shown in the UI, so collapse the runs."""
          return " ".join((row.get("SiteName") or "").split()) or None


      def pollutant_entry(row, distance):
          cat = row.get("Category")
          # dataType=B carries the raw concentration in "Value" (not
          # "Concentration"); -999 is the missing-data sentinel here too.
          value = row.get("Value")
          return {
              "parameter": row.get("Parameter"),
              "aqi": int(row["AQI"]),
              "category": CATEGORY_NAMES.get(cat) if isinstance(cat, int) else None,
              "station": site_name(row),
              "agency": row.get("AgencyName"),
              "distanceMiles": round(distance, 1),
              "concentration": value if isinstance(value, (int, float))
              and not isinstance(value, bool) and value >= 0 else None,
              "unit": row.get("Unit"),
              "observedAt": row.get("UTC"),
          }


      def resolve(index, loc, rows):
          """Nearest station *per pollutant* for one configured location.

          Not one nearest station: Crystal Mountain's two closest monitors are
          seasonal ozone-only sites (the "(SO)" suffix), so a naive nearest-wins
          rule would hand it an ozone reading and never measure smoke at all —
          the failure that matters most in fire season.
          """
          point = coords(loc)
          if point is None:
              return blank(index)
          lat, lon = point

          nearest = {}
          for row in rows:
              d = miles_between(lat, lon, row["Latitude"], row["Longitude"])
              if d > max_miles:
                  continue
              param = row["Parameter"]
              seen = nearest.get(param)
              if seen is None or d < seen[0]:
                  nearest[param] = (d, row)

          if not nearest:
              log(f"location {index}: no station within {max_miles:g} mi")
              return blank(index)

          pollutants = [pollutant_entry(row, d) for d, row in nearest.values()]
          pollutants.sort(key=lambda p: (-p["aqi"], p["distanceMiles"]))
          # The headline is the worst pollutant, and the category shown is that
          # same dominant pollutant's — this is how AirNow's own site reports it.
          top = pollutants[0]
          return {
              "index": index,
              "aqi": top["aqi"],
              "category": top["category"],
              "ok": True,
              "pollutant": top["parameter"],
              "station": top["station"],
              "distanceMiles": top["distanceMiles"],
              "pollutants": pollutants,
          }


      # No key configured yet: write a well-formed empty payload rather than
      # erroring, so a Hearth build without the key still serves the dashboard
      # (the widget renders "ACI —"). Mirrors intranet-calendar.nix's early exit.
      if not key:
          log("airnowApiKey unset; writing empty payload")
          write({"generatedAt": int(time.time()), "pollSeconds": poll, "locations": []})
          sys.exit(0)

      points = [p for p in (coords(loc) for loc in locations) if p is not None]
      if not points:
          log("no locations with coordinates; writing empty payload")
          write({"generatedAt": int(time.time()), "pollSeconds": poll, "locations": []})
          sys.exit(0)

      rows = fetch_rows(points)
      if rows is None:
          # Fail open, as the per-location poll did: a well-formed payload of
          # blanks so the widget shows "—" rather than a stale or broken figure.
          write({"generatedAt": int(time.time()), "pollSeconds": poll,
                 "locations": [blank(i) for i, _ in enumerate(locations)]})
          sys.exit(0)

      rows = latest_by_station(rows)
      log(f"airnow: {len(rows)} station/parameter readings in box")

      # One entry per configured location, in config order, carrying its own
      # index. The widget renders a filtered subset of locations, so it matches
      # on this index rather than on array position.
      results = [resolve(i, loc, rows) for i, loc in enumerate(locations)]
      for r in results:
          if r["ok"]:
              log(f"location {r['index']}: {r['pollutant']} {r['aqi']} "
                  f"from {r['station']} at {r['distanceMiles']} mi")
      log(f"{sum(1 for r in results if r['ok'])}/{len(results)} locations ok")

      write({
          "generatedAt": int(time.time()),
          "pollSeconds": poll,
          "maxStationMiles": max_miles,
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

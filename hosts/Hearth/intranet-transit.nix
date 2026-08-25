# Oneshot + timer: one Hearth poll of Puget Sound OneBusAway (Sound Transit OTD)
# → /run/hearth-intranet/transit.json. Browsers only read that file.
# Do not proxy OBA per client (TEST key 429s). Do not call Houston METRO.
{pkgs, ...}: let
  transitCfg = (import ./intranet/config).transit;
  pollSeconds = let
    n = transitCfg.obaPollSeconds or 60;
  in
    if n < 60
    then 60
    else n;
  pollCfg = pkgs.writeText "hearth-transit-poll.json" (builtins.toJSON {
    key = transitCfg.obaApiKey or "TEST";
    pollSeconds = pollSeconds;
    stops = transitCfg.busStops or [];
  });
  writer = pkgs.writeShellApplication {
    name = "hearth-intranet-transit";
    runtimeInputs = [pkgs.coreutils pkgs.python3];
    text = ''
      set -euo pipefail
      mkdir -p /run/hearth-intranet
      python3 - ${pollCfg} <<'PY'
      import json, os, sys, time, urllib.error, urllib.parse, urllib.request

      cfg = json.load(open(sys.argv[1], encoding="utf-8"))
      out = "/run/hearth-intranet/transit.json"
      key = cfg.get("key") or "TEST"
      poll = max(60, int(cfg.get("pollSeconds") or 60))
      stops_in = cfg.get("stops") or []

      # Seconds between stop requests. Two back-to-back calls on the shared
      # TEST key trip OBA's burst limit and one stop comes back 429.
      STAGGER = 2.0
      RETRY_AFTER = 5.0
      # Carry a 429'd stop's last arrivals only this long. Long enough to ride
      # out a few bad cycles, short enough that the times still mean something.
      MAX_CARRY_AGE = 300


      def log(msg):
          print(msg, file=sys.stderr, flush=True)


      def previous():
          try:
              with open(out, encoding="utf-8") as fh:
                  return json.load(fh)
          except Exception:
              return {}


      prev_stops = {}
      for row in (previous().get("stops") or []):
          if row.get("id"):
              prev_stops[str(row["id"])] = row


      def oba_id(posted):
          posted = str(posted)
          return posted if "_" in posted else f"1_{posted}"


      def skip_stop(stop):
          if not isinstance(stop, dict):
              return False
          feed = str(stop.get("feed") or "").lower()
          if stop.get("skip") or feed in ("houston", "metro"):
              return True
          posted = str(stop.get("id") or stop.get("stopId") or "")
          # Houston METRO codes from an older dashboard list — not OBA ids.
          return posted in ("25027", "25028")


      def fetch_stop(stop):
          if isinstance(stop, str):
              stop = {"id": stop}
          posted = str(stop.get("id") or stop.get("stopId") or "")
          oid = oba_id(posted)
          name = stop.get("name") or ""
          url = (
              "https://api.pugetsound.onebusaway.org/api/where/"
              f"arrivals-and-departures-for-stop/{urllib.parse.quote(oid)}.json?"
              + urllib.parse.urlencode({"key": key, "minutesAfter": "60"})
          )
          data = None
          status = 0
          try:
              req = urllib.request.Request(url, headers={"User-Agent": "hearth-intranet-transit"})
              with urllib.request.urlopen(req, timeout=20) as resp:
                  status = resp.status
                  data = json.load(resp)
          except urllib.error.HTTPError as exc:
              status = exc.code
              try:
                  data = json.loads(exc.read().decode("utf-8", errors="replace"))
              except Exception:
                  data = None
          except Exception:
              return {
                  "id": posted,
                  "obaId": oid,
                  "name": name,
                  "ok": False,
                  "status": 0,
                  "code": 0,
                  "currentTime": None,
                  "arrivals": [],
              }

          code = (data or {}).get("code", status)
          refs = ((data or {}).get("data") or {}).get("references") or {}
          stop_name = name
          for ref in refs.get("stops") or []:
              if ref.get("id") == oid:
                  stop_name = name or ref.get("name") or posted
                  break
          ads = (((data or {}).get("data") or {}).get("entry") or {}).get("arrivalsAndDepartures") or []
          arrivals = []
          for row in ads:
              arrivals.append({
                  "routeShortName": row.get("routeShortName") or "?",
                  "tripHeadsign": row.get("tripHeadsign") or "",
                  "predictedArrivalTime": int(row.get("predictedArrivalTime") or 0),
                  "scheduledArrivalTime": int(row.get("scheduledArrivalTime") or 0),
                  "predicted": bool(row.get("predicted")),
              })
          arrivals.sort(key=lambda r: (r["predictedArrivalTime"] or r["scheduledArrivalTime"]))
          return {
              "id": posted,
              "obaId": oid,
              "name": stop_name,
              "ok": code == 200,
              "status": status,
              "code": code,
              "currentTime": (data or {}).get("currentTime"),
              "arrivals": arrivals[:6],
          }

      def is_429(row):
          return row.get("status") == 429 or row.get("code") == 429


      def carry_forward(row):
          prev = prev_stops.get(str(row.get("id")))
          if not prev or not (prev.get("arrivals") or []):
              return row
          # Age is measured from OBA's own currentTime, which a carried row
          # keeps. Using the file's generatedAt would never expire, because we
          # rewrite the file every cycle even while every stop is 429ing.
          captured = int(prev.get("currentTime") or 0)
          if not captured or (time.time() * 1000 - captured) > MAX_CARRY_AGE * 1000:
              return row
          merged = dict(row)
          merged["arrivals"] = prev["arrivals"]
          merged["currentTime"] = captured
          merged["stale"] = True
          return merged


      wanted = [s if isinstance(s, dict) else {"id": s} for s in stops_in]
      wanted = [s for s in wanted if not skip_stop(s)]

      results = []
      for index, stop in enumerate(wanted):
          if index:
              time.sleep(STAGGER)
          row = fetch_stop(stop)
          if is_429(row):
              log(f"stop {row.get('id')}: 429, retrying once in {RETRY_AFTER:.0f}s")
              time.sleep(RETRY_AFTER)
              row = fetch_stop(stop)
              if is_429(row):
                  row = carry_forward(row)
                  kept = len(row.get("arrivals") or [])
                  log(f"stop {row.get('id')}: still 429, carrying {kept} cached arrivals")
          if not is_429(row):
              log(f"stop {row.get('id')}: status {row.get('status')} arrivals {len(row.get('arrivals') or [])}")
          results.append(row)

      limited = any(is_429(r) for r in results)
      payload = {
          "generatedAt": int(time.time()),
          "pollSeconds": poll,
          "limited": limited,
          "stops": results,
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
  systemd.services.hearth-intranet-transit = {
    description = "Write Hearth intranet transit.json from OneBusAway";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "hearth-intranet";
      Group = "hearth-intranet";
      ExecStart = "${writer}/bin/hearth-intranet-transit";
      # Staggering plus a retry per stop lengthens the worst case; do not let a
      # hung fetch stall polling indefinitely.
      TimeoutStartSec = "90s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = ["/run/hearth-intranet"];
    };
  };

  systemd.timers.hearth-intranet-transit = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "15s";
      OnUnitActiveSec = "${toString pollSeconds}s";
      # OnUnitActiveSec counts from deactivation, so run time and timer slack
      # both push the real cadence past pollSeconds. Keep the slack small; the
      # widget no longer assumes an exact period either.
      AccuracySec = "1s";
      Unit = "hearth-intranet-transit.service";
    };
  };
}

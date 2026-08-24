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

      results = [fetch_stop(s) for s in stops_in if not skip_stop(s if isinstance(s, dict) else {"id": s})]
      limited = any(r.get("status") == 429 or r.get("code") == 429 for r in results)
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
      AccuracySec = "5s";
      Unit = "hearth-intranet-transit.service";
    };
  };
}

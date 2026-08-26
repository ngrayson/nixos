# Daily inclement-weather heads-up to the Hearthchime Discord webhook.
# Server-side only: Open-Meteo forecast + AQI, one post or silence. Fail-open
# like hearth-notify — never print the webhook URL. Config lives in
# intranet/config/alerts/ (not a browser widget).
{
  lib,
  pkgs,
  ...
}: let
  checkout = let
    env = builtins.getEnv "NIXOS_DIR";
    home = builtins.getEnv "HOME";
  in
    if env != ""
    then env
    else if home != ""
    then "${home}/.config/nixos"
    else "";

  local = "${checkout}/hosts/Hearth/intranet/config/alerts/config.nix";
  example = ./intranet/config/alerts/config.example.nix;
  loaded =
    if checkout != "" && builtins.pathExists (/. + local)
    then import (/. + local)
    else import example;

  defaults = {
    enable = true;
    time = "07:00";
    place = "Kirkland";
    latitude = 47.6774;
    longitude = -122.1982;
    linkUrl = null;
    thresholds = {
      windGustMph = 30;
      highTempF = 90;
      lowTempF = 25;
      precipProbabilityPct = 60;
      snowfallIn = 0.1;
      usAqi = 100;
    };
  };

  cfg =
    defaults
    // loaded
    // {
      thresholds = defaults.thresholds // (loaded.thresholds or {});
    };

  settings = pkgs.writeText "hearth-weather-alert.json" (builtins.toJSON {
    place = cfg.place;
    latitude = cfg.latitude;
    longitude = cfg.longitude;
    linkUrl = cfg.linkUrl;
    thresholds = cfg.thresholds;
  });

  writer = pkgs.writeShellApplication {
    name = "hearth-weather-alert";
    runtimeInputs = [pkgs.coreutils pkgs.python3];
    text = ''
      set -euo pipefail
      export HEARTH_WEATHER_ALERT_SETTINGS="${settings}"
      python3 - <<'PY'
      import json, os, sys, urllib.error, urllib.request

      settings_path = os.environ["HEARTH_WEATHER_ALERT_SETTINGS"]
      cfg = json.load(open(settings_path, encoding="utf-8"))
      dry = os.environ.get("HEARTH_WEATHER_ALERT_DRY_RUN", "") == "1"
      webhook_file = os.environ.get(
          "HEARTH_NOTIFY_WEBHOOK_FILE", "/run/secrets/hearth-discord-webhook"
      )

      lat = cfg["latitude"]
      lon = cfg["longitude"]
      place = cfg.get("place") or "Kirkland"
      th = cfg["thresholds"]
      link = cfg.get("linkUrl") or (
          f"https://forecast.weather.gov/MapClick.php?lat={lat}&lon={lon}"
      )

      def log(msg):
          print(msg, file=sys.stderr, flush=True)

      def fetch(url):
          req = urllib.request.Request(
              url, headers={"User-Agent": "hearth-weather-alert"}
          )
          with urllib.request.urlopen(req, timeout=20) as resp:
              return json.load(resp)

      def first(series, default=None):
          if not series:
              return default
          value = series[0]
          return default if value is None else value

      def join_en(items):
          if not items:
              return ""
          if len(items) == 1:
              return items[0]
          if len(items) == 2:
              return f"{items[0]} and {items[1]}"
          return ", ".join(items[:-1]) + f", and {items[-1]}"

      forecast_url = (
          "https://api.open-meteo.com/v1/forecast"
          f"?latitude={lat}&longitude={lon}"
          "&daily=temperature_2m_max,temperature_2m_min,"
          "precipitation_probability_max,wind_gusts_10m_max,"
          "snowfall_sum,weather_code"
          "&forecast_days=1"
          "&temperature_unit=fahrenheit"
          "&wind_speed_unit=mph"
          "&precipitation_unit=inch"
          "&timezone=America%2FLos_Angeles"
      )
      aqi_url = (
          "https://air-quality-api.open-meteo.com/v1/air-quality"
          f"?latitude={lat}&longitude={lon}"
          "&hourly=us_aqi"
          "&forecast_days=1"
          "&timezone=America%2FLos_Angeles"
      )

      try:
          daily = fetch(forecast_url).get("daily") or {}
      except Exception as exc:
          log(f"forecast fetch failed: {type(exc).__name__}")
          sys.exit(0)

      try:
          aqi_hours = (fetch(aqi_url).get("hourly") or {}).get("us_aqi") or []
          aqi_vals = [n for n in aqi_hours if n is not None]
          aqi = max(aqi_vals) if aqi_vals else None
      except Exception as exc:
          log(f"aqi fetch failed: {type(exc).__name__}")
          aqi = None

      high = first(daily.get("temperature_2m_max"))
      low = first(daily.get("temperature_2m_min"))
      precip = first(daily.get("precipitation_probability_max"))
      gust = first(daily.get("wind_gusts_10m_max"))
      snow = first(daily.get("snowfall_sum"), 0) or 0
      code = first(daily.get("weather_code"))
      try:
          code = int(code) if code is not None else None
      except (TypeError, ValueError):
          code = None

      hits = []
      if gust is not None and gust >= th["windGustMph"]:
          hits.append(f"gusts up to {gust:.0f} mph")
      if precip is not None and precip >= th["precipProbabilityPct"]:
          hits.append("rain likely")
      if snow >= th["snowfallIn"]:
          hits.append("snow in the forecast")
      if high is not None and high >= th["highTempF"]:
          hits.append(f"a high around {high:.0f}°F")
      if low is not None and low <= th["lowTempF"]:
          hits.append(f"a low around {low:.0f}°F")
      if aqi is not None and aqi >= th["usAqi"]:
          hits.append(f"air quality around {aqi:.0f}")
      if code in (96, 99):
          hits.append("thunderstorms with hail")
      elif code == 95:
          hits.append("thunderstorms")
      if code in (56, 57, 66, 67):
          hits.append("freezing rain")

      if not hits:
          log("quiet day; no Discord post")
          sys.exit(0)

      content = (
          f"Good morning! Heads up — {join_en(hits)} today in {place}. "
          f"Take care out there. {link}"
      )
      if dry:
          print(content)
          sys.exit(0)

      if not os.path.isfile(webhook_file) or not os.access(webhook_file, os.R_OK):
          log("webhook file missing; skip Discord")
          sys.exit(0)
      try:
          url = open(webhook_file, encoding="utf-8").read().strip()
      except OSError:
          log("webhook file unreadable; skip Discord")
          sys.exit(0)
      if not url:
          log("webhook file empty; skip Discord")
          sys.exit(0)

      payload = json.dumps({"content": content}).encode("utf-8")
      req = urllib.request.Request(
          url,
          data=payload,
          method="POST",
          headers={"Content-Type": "application/json", "User-Agent": "hearth-weather-alert"},
      )
      try:
          with urllib.request.urlopen(req, timeout=10) as resp:
              resp.read()
      except Exception:
          log("Discord post failed; skipping")
      sys.exit(0)
      PY
    '';
  };
in
  lib.mkIf (cfg.enable or true) {
    systemd.services.hearth-weather-alert = {
      description = "Daily Hearthchime inclement-weather heads-up";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = "wiz";
        Group = "users";
        ExecStart = "${writer}/bin/hearth-weather-alert";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        TimeoutStartSec = "60s";
      };
    };

    systemd.timers.hearth-weather-alert = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* ${cfg.time}:00 America/Los_Angeles";
        Persistent = true;
        AccuracySec = "1min";
        Unit = "hearth-weather-alert.service";
      };
    };
  }

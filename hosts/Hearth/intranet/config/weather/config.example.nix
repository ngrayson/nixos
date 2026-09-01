# Template only. Copy to config.nix (gitignored) for the Hearth build.
# ACI (the dashboard's AQI reading) comes from AirNow, not Open-Meteo:
# hearth-intranet-aqi polls https://www.airnowapi.org/aq/data/ once per interval
# and writes /run/hearth-intranet/aqi.json, one entry per location below in
# this same order. The page only reads /aqi.json — the key never reaches a
# browser. AirNow reports real EPA monitoring-station readings; Open-Meteo's
# us_aqi is a modeled value and disagrees with AirNow.gov and most apps.
# airnowApiKey is free and self-serve from https://docs.airnowapi.org/account/request/
# Set it here in the gitignored config.nix only — never in this example file
# and never in a commit. Leaving it empty is safe: the poller writes an empty
# payload and every location shows "ACI —".
# Poll no faster than 300s; AirNow observations only update about hourly.
{
  # "F" or "C" — Open-Meteo temperature_unit.
  temperatureUnit = "F";
  # Per location, `detail` is "long" (default) or "short".
  # long: temp, sky, wind, ACI, plus sun/moon rise/set and moon phase.
  # short: temp, sky, wind, ACI only.
  # Do not put real home coordinates here.
  locations = [];
  airnowApiKey = "";
  airnowPollSeconds = 600;
  # How far a monitoring station may be from a location and still speak for it.
  # Resolved per pollutant, so a location whose only nearby sites are seasonal
  # ozone-only monitors reports ozone and simply has no PM2.5, rather than
  # reaching tens of miles for one. Raise it and a location starts borrowing
  # readings from the far side of a mountain range.
  airnowMaxStationMiles = 25;
}

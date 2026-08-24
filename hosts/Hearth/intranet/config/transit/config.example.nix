# Template only. Copy to config.nix (gitignored) for the Hearth build.
# Buses: hearth-intranet-transit polls
# https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/{id}.json
# once per interval and writes /run/hearth-intranet/transit.json.
# The page only reads /transit.json (not a Caddy /transit/oba proxy).
# busStops is a list. `id` is the posted Metro stop number (OBA uses 1_<id>)
# or a full agency_stop id. Optional `name` is display-only.
# Houston METRO ids are not OBA — set skip = true (or feed = "houston") so
# they stay in the list without being queried. 25027 / 25028 are skipped.
# obaApiKey "TEST" is the public OBA development key, not a Bitwarden secret.
# It 429s if polled hard. Poll no faster than 60s (Hearth-side).
{
  # Waze iframe (`lat,lon`). Official params have no traffic toggle.
  # Livemap georss 403s as of 2026-08, so the embed is a basemap only.
  # Do not swap providers here. Do not put a real home map center here.
  mapQuery = "";
  mapZoom = 10;
  obaApiKey = "TEST";
  obaPollSeconds = 60;
  busStops = [];
}

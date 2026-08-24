# Template only. Copy to config.nix (gitignored) for the Hearth build.
# Buses: hearth-intranet-transit polls OneBusAway once per interval and
# writes /run/hearth-intranet/transit.json. The page only reads that file.
# busStops is a list. `id` is the posted Metro stop number (OBA uses 1_<id>).
# Optional `name` is display-only.
# obaApiKey "TEST" is the public OBA development key; it 429s if polled hard.
# Poll no faster than 60s (Hearth-side; not per browser).
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

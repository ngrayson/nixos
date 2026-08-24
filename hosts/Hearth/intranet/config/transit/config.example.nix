# Flake reads this file. A sibling `config.nix` is ignored (gitignored).
# Buses: hearth-intranet-transit polls OneBusAway once per interval and
# writes /run/hearth-intranet/transit.json. The page only reads that file.
# busStops is a list. `id` is the posted Metro stop number (OBA uses 1_<id>).
# Optional `name` is display-only.
# obaApiKey "TEST" is the public OBA development key; it 429s if polled hard.
# Poll no faster than 60s (Hearth-side; not per browser).
{
  # Waze Live Map (traffic on, no API key). Centered on the Kirkland stops.
  # Google's Maps iframe cannot show traffic without a JS API key.
  mapQuery = "47.635754,-122.235235";
  mapZoom = 10;
  obaApiKey = "TEST";
  obaPollSeconds = 60;
  busStops = [
    {
      id = "70665";
      name = "Central Way & 5th St";
    }
    {
      id = "70676";
      name = "6th St & Kirkland Way";
    }
  ];
}

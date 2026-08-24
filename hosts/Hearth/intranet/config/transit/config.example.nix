# Flake reads this file. A sibling `config.nix` is ignored (gitignored).
# Buses: Caddy handle_path /transit/oba/* → Puget Sound OneBusAway
#   GET /api/where/arrivals-and-departures-for-stop/{id}.json
# busStops is a list. `id` is the posted Metro stop number (OBA uses 1_<id>).
# Optional `name` is display-only. JS searches BUS_ENDPOINT.
# obaApiKey "TEST" is the public OBA development key; it 429s if polled hard.
# Poll no faster than 60s.
{
  routeFrom = "Hearth";
  routeTo = "Tawa";
  obaApiKey = "TEST";
  obaPollSeconds = 60;
  busStops = [
    {
      id = "70665";
      name = "Central Way & 5th St";
    }
    {
      id = "53550";
      name = "Kirkland Way & 6th St";
    }
  ];
}

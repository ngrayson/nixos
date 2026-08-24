# Flake reads this file. A sibling `config.nix` is ignored (gitignored).
{
  # "F" or "C" — Open-Meteo temperature_unit.
  temperatureUnit = "F";
  # Per location, `detail` is "long" (default) or "short".
  # long: temp, sky, wind, ACI, plus sun/moon rise/set and moon phase.
  # short: temp, sky, wind, ACI only.
  locations = [
    {
      name = "Kirkland";
      latitude = 47.6774;
      longitude = -122.1982;
      detail = "long";
    }
    {
      name = "Seattle";
      latitude = 47.6062;
      longitude = -122.3321;
      detail = "short";
    }
    {
      name = "Crystal Mountain";
      latitude = 46.9369;
      longitude = -121.4891;
      detail = "short";
    }
  ];
}

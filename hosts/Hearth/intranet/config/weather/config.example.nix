# Flake reads this file. A sibling `config.nix` is ignored (gitignored).
{
  # "F" or "C" — Open-Meteo temperature_unit.
  temperatureUnit = "F";
  # Per location, `detail` is "long" (default) or "short".
  # long: temp, sky, wind, ACI, plus sun/moon rise/set and moon phase.
  # short: temp, sky, wind, ACI only.
  locations = [
    {
      name = "Houston";
      latitude = 29.7604;
      longitude = -95.3698;
      detail = "long";
    }
  ];
}

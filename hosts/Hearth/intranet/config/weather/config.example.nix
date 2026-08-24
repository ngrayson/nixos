# Flake reads this file. A sibling `config.nix` is ignored (gitignored).
{
  # "F" or "C" — Open-Meteo temperature_unit.
  temperatureUnit = "F";
  locations = [
    {
      name = "Seattle";
      latitude = 47.6062;
      longitude = -122.3321;
    }
    {
      name = "Houston";
      latitude = 29.7604;
      longitude = -95.3698;
    }
  ];
}

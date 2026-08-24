# Flake reads this file. A sibling `config.nix` is ignored (gitignored).
{
  # "F" or "C" — Open-Meteo temperature_unit.
  temperatureUnit = "F";
  locations = [
    {
      name = "Houston";
      latitude = 29.7604;
      longitude = -95.3698;
    }
  ];
}

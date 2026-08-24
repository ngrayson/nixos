# Template only. Copy to config.nix (gitignored) for the Hearth build.
{
  # "F" or "C" — Open-Meteo temperature_unit.
  temperatureUnit = "F";
  # Per location, `detail` is "long" (default) or "short".
  # long: temp, sky, wind, ACI, plus sun/moon rise/set and moon phase.
  # short: temp, sky, wind, ACI only.
  # Do not put real home coordinates here.
  locations = [];
}

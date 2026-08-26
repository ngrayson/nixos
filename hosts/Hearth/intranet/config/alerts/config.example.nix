# Template. Copy to config.nix (gitignored) to override. Defaults are Kirkland
# at 07:00 America/Los_Angeles. This is not a browser widget — weather-alert.nix
# imports it directly.
{
  enable = true;
  time = "07:00"; # OnCalendar hour:minute, America/Los_Angeles
  place = "Kirkland";
  latitude = 47.6774;
  longitude = -122.1982;
  # null → weather.gov MapClick for lat/lon
  linkUrl = null;
  thresholds = {
    windGustMph = 30;
    highTempF = 90;
    lowTempF = 25;
    precipProbabilityPct = 60;
    snowfallIn = 0.1;
    usAqi = 100;
  };
}

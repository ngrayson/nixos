# Server-safe defaults shared by workstation and cloud profiles.
{...}: {
  # US Pacific. Not America/Vancouver: tzdata 2026c put BC on permanent UTC-7 from 2026-11-01.
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_CA.UTF-8";

  nix.settings.experimental-features = ["nix-command" "flakes"];
  nixpkgs.config.allowUnfree = true;
}

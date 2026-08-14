# Server-safe defaults shared by workstation and cloud profiles.
{...}: {
  time.timeZone = "America/Vancouver";
  i18n.defaultLocale = "en_CA.UTF-8";

  nix.settings.experimental-features = ["nix-command" "flakes"];
  nixpkgs.config.allowUnfree = true;
}

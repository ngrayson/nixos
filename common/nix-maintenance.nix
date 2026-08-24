# Per-host Nix GC + store hardlink + optional systemd-boot generation cap.
# Import from hosts/<Name>/host.nix with that machine's numbers. Do not put
# host-specific cutoffs in common/base.nix.
{
  dates,
  deleteOlderThan,
  configurationLimit ? null,
}: {lib, ...}: {
  nix.gc.automatic = true;
  nix.gc.dates = dates;
  nix.gc.options = "--delete-older-than ${deleteOlderThan}";
  nix.settings.auto-optimise-store = true;
  boot.loader.systemd-boot.configurationLimit =
    lib.mkIf (configurationLimit != null) configurationLimit;
}

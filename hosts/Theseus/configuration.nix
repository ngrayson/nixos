# Entry module for host Theseus (Framework laptop). Build with:
#   os-rebuild build --host Theseus
# hardware-configuration.nix is the real disk map (/, /boot, partition swap).
# Confirm UUIDs on-box before activate. Once swap is verified on Theseus,
# uncomment ./hibernate.nix (do not enable it from a docs-only change).
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../common/system.nix
    ./hardware-configuration.nix
    ./host.nix
    # ./hibernate.nix
  ];
}

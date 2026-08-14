# Entry module for host Theseus (Framework laptop). Build with:
#   os-rebuild build --host Theseus
# Before first deploy on real hardware, replace ./hardware-configuration.nix with
# `nixos-generate-config` output (see file header there). Once its partition-backed
# swapDevices entry is verified, add ./hibernate.nix to imports.
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

# Entry module for host Theseus (Framework laptop). Build with:
#   os-rebuild build --host Theseus
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../common/system.nix
    ./hardware-configuration.nix
    ./host.nix
    ./hibernate.nix
  ];
}

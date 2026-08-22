# Entry module for host Tawa. Build with:
#   os-rebuild build --host Tawa
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../profiles/workstation.nix
    ./hardware-configuration.nix
    ./host.nix
  ];
}

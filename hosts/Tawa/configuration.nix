# Entry module for host Tawa. Build with:
#   os-rebuild build --host Tawa
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../profiles/workstation.nix
    ../../common/sops.nix
    ./hardware-configuration.nix
    ./host.nix
    ./remote-access.nix
    # Conveyor Personal Compute VM (Lima >= 2.2, linger, kvm). Tawa only.
    ../../common/conveyor-k3.nix
  ];
}

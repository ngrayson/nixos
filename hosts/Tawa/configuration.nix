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
    ../../common/vscode-policy.nix
    ./remote-access.nix
    # Conveyor Personal Compute VM (Lima >= 2.2, linger, kvm). Tawa only.
    ../../common/conveyor-k3.nix
  ];
}

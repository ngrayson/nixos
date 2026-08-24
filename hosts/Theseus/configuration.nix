# Entry module for host Theseus (Framework laptop). Build with:
#   os-rebuild build --host Theseus
# After switch, join the tailnet once: `sudo tailscale up` (browser login).
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../common/system.nix
    ../../common/tailscale.nix
    ./hardware-configuration.nix
    ./host.nix
    # ./hibernate.nix
  ];
}

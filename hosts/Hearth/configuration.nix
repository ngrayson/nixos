# Entry module for host Hearth (Surface Laptop 3 media host). Build with:
#   os-rebuild build --host Hearth
{...}: {
  imports = [
    ../../profiles/media-server.nix
    ../../common/sops.nix
    ./hardware-configuration.nix
    ./host.nix
    ./jellyfin.nix
    ./remote-access.nix
    ./caddy.nix
  ];
}

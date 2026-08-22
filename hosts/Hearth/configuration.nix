# Entry module for host Hearth (Surface Laptop 3 media host). Build with:
#   os-rebuild build --host Hearth
{...}: {
  imports = [
    ../../profiles/media-desktop.nix
    ./hardware-configuration.nix
    ./host.nix
    ./jellyfin.nix
    ./remote-access.nix
    ./home.nix
  ];
}

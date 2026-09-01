# Entry module for host Hearth (Surface Laptop 3 media host). Build with:
#   os-rebuild build --host Hearth
# Still the Hyprland media-desktop. profiles/media-server.nix + home/server.nix
# are the H4 headless flip — import those instead of media-desktop/home.nix
# only when Nick is ready to drop the greeter.
{...}: {
  imports = [
    ../../profiles/media-desktop.nix
    ../../common/sops.nix
    ./hardware-configuration.nix
    ./host.nix
    ./disk.nix
    ./jellyfin.nix
    ./remote-access.nix
    ./home.nix
    ./caddy.nix
    ./intranet-runtime.nix
    ./intranet-status.nix
    ./intranet-transit.nix
    ./intranet-aqi.nix
    ./intranet-gallery.nix
    ./intranet-calendar.nix
    ./intranet-maps-key.nix
    ./weather-alert.nix
    ./restic.nix
    ./syncthing.nix
    ./ingest.nix
  ];
}

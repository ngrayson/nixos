# Entry module for host Hearth (Surface Laptop 3 media host). Build with:
#   os-rebuild build --host Hearth
#
# Headless since 2026-09-01 (H4): profiles/media-server.nix + home/server.nix,
# SSH shell only, no Hyprland and no greeter. Rolling back is a one-line swap
# to ../../profiles/media-desktop.nix plus re-adding ./home.nix, which holds
# the desktop-only overrides (GTK icons, touchpad, lid binds, idle lock) and
# is kept in the tree for exactly that reason.
#
# Recovery if a headless boot goes wrong is the previous boot generation at
# the bootloader — the lid stays `ignore` in host.nix, so the machine keeps
# running with the lid shut either way.
{...}: {
  imports = [
    ../../profiles/media-server.nix
    ../../common/sops.nix
    ./hardware-configuration.nix
    ./host.nix
    ./disk.nix
    ./jellyfin.nix
    ./remote-access.nix
    ./caddy.nix
    ./intranet-runtime.nix
    ./intranet-status.nix
    ./intranet-transit.nix
    ./intranet-aqi.nix
    ./intranet-gallery.nix
    ./intranet-calendar.nix
    ./intranet-maps-key.nix
    ./weather-alert.nix
    ./battery-alert.nix
    ./go3-battery-alert.nix
    ./restic.nix
    ./syncthing.nix
    ./ingest.nix
  ];
}

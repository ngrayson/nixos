# Entry module for host Go3 (Surface Go 3 kiosk). Build with:
#   os-rebuild build --host Go3
# Activate from Tawa over SSH, the way Hearth is deployed. Never run
# `os-rebuild switch --host Go3` on Tawa — that switches Tawa.
{...}: {
  imports = [
    ../../profiles/kiosk.nix
    ./hardware-configuration.nix
    ./host.nix
    ./remote-access.nix
    ./idle-blank.nix
    ./ambient-brightness.nix
    ./stats-server.nix
  ];
}

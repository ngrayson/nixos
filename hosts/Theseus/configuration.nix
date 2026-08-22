# Entry module for host Theseus (Framework laptop). Build with:
#   os-rebuild build --host Theseus
# hardware-configuration.nix is the real disk map (/, /boot, partition swap).
# Confirm UUIDs on-box before activate. Prefer `os-rebuild boot` on Theseus
# for resume-device changes, then reboot.
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../profiles/workstation.nix
    ./hardware-configuration.nix
    ./host.nix
    ./hibernate.nix
  ];
}

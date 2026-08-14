# Theseus (Framework laptop) — hostname, LUKS, hibernation, and host overrides.
# The Framework AMD AI 300 module is imported by flake.nix.
{...}: {
  networking.hostName = "Theseus";
  system.stateVersion = "26.05";

  # boot.initrd.luks.devices."luks-…".device = "/dev/disk/by-uuid/…";
  # boot.kernelParams = [ ];
}

# Theseus (Framework laptop) — hostname, nixos-hardware, LUKS, kernelParams.
{...}: {
  imports = [
    # After adding nixos-hardware to flake or channel:
    # <nixos-hardware/framework/13-inch/amd-ai-300-series>
  ];

  networking.hostName = "Theseus";

  # boot.initrd.luks.devices."luks-…".device = "/dev/disk/by-uuid/…";
  # boot.kernelParams = [ ];
}

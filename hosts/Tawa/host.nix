# Tawa (desktop) — hostname, optional nixos-hardware, LUKS, kernelParams.
# Other hosts: add `hosts/<name>/host.nix` with their `networking.hostName` and imports.
{...}: {
  imports = [
    # <nixos-hardware/framework/13-inch/amd-ai-300-series>
  ];

  networking.hostName = "Tawa";

  # boot.initrd.luks.devices."luks-…".device = "/dev/disk/by-uuid/…";
  # boot.kernelParams = ["amd_pstate=active"];
}

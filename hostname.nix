# Theseus — machine identity, CPU/boot knobs, and nixos-hardware.
# For another host: create `hostname-Other.nix` or edit this file; keep LUKS names/UUIDs in sync with
# that machine’s `hardware-configuration.nix` and `boot.initrd.luks.devices` (see MIGRATION.md).
{...}: {
  imports = [
    # <nixos-hardware/framework/13-inch/amd-ai-300-series>
  ];

  networking.hostName = "Tawa";

  # Swap LUKS (root LUKS is in `hardware-configuration.nix` from the installer)
  # boot.initrd.luks.devices."luks-61d676d2-6e31-41cd-a953-13d2bf0fd257".device = "/dev/disk/by-uuid/61d676d2-6e31-41cd-a953-13d2bf0fd257";

  # CPU — clear or replace on Intel / different platforms
  # boot.kernelParams = ["amd_pstate=active"];
}

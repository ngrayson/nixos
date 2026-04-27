# STUB — not for production use on disk.
#
# On the Framework laptop (installer or first boot), run:
#   nixos-generate-config --root /mnt
# and merge/replace this file with the generated hardware-configuration.nix
# (fileSystems, swap, initrd modules, LUKS). Keep the comment at the top of
# the generated file or adapt paths to match this repo layout.
#
# This placeholder exists so `nix build -I nixos-config=…/hosts/Theseus/configuration.nix`
# evaluates from any machine; UUIDs below are invalid until you replace them.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "usb_storage" "usbhid" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/00000000-0000-4000-8000-000000000001";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/00000000-0000-4000-8000-000000000002";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  swapDevices = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}

# Go3 (Surface Go 3) — hostname, mainline kernel, kiosk power policy, swap.
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    (import ../../common/nix-maintenance.nix {
      dates = "weekly";
      deleteOlderThan = "14d";
      configurationLimit = 5;
    })
  ];

  networking.hostName = "Go3";

  # The linux-surface patched kernel (microsoft-surface-common, wired in
  # flake.nix) builds from source with no binary cache. This machine needs
  # none of it: the Type Cover is USB HID rather than the SAM aggregator, the
  # touchscreen is I2C-HID (per nixos-hardware, the Surface Go range is the
  # exception that does NOT use IPTS), and the radio is stock Intel.
  # Confirmed on-box 2026-08-31 on mainline: iwlwifi bound, and Bluetooth
  # reported `Found device firmware: intel/ibt-20-1-3.sfi`.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  # 7.7 GiB usable. One Chromium left running for months: zram absorbs the
  # churn and the swapfile is the leak backstop. nixos-generate-config left
  # swapDevices empty on purpose — no swap partition was created.
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4 * 1024;
    }
  ];

  # Kiosk pose: always on, nobody at the console. Never suspend on lid, and
  # never let a passer-by halt it with the power button. Display blanking and
  # camera wake are deliberately NOT here — that is the follow-up card.
  services.logind.settings.Login = {
    HandleLidSwitch = lib.mkForce "ignore";
    HandleLidSwitchExternalPower = lib.mkForce "ignore";
    HandleLidSwitchDocked = lib.mkForce "ignore";
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "poweroff";
  };

  # First install of this machine was 26.05 — never bump.
  system.stateVersion = "26.05";
}

# Hearth (Surface Laptop 3) — hostname, surface kernel, media-host power, touchpad.
{
  lib,
  pkgs,
  ...
}: {
  networking.hostName = "Hearth";

  # Patched linux-surface kernel (module wired in flake.nix).
  hardware.microsoft-surface.kernelVersion = "stable";
  # linux-surface 6.19.8 is built from source with no binary cache. This Ice Lake
  # machine already enumerates IPTS + the HID touchpad on mainline 6.18; use the
  # nixpkgs kernel until a remote or cached surface kernel is available.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  zramSwap.enable = true;
  zramSwap.memoryPercent = 25;

  # Lid closed on AC: keep serving Jellyfin. On battery, still suspend.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "poweroff";
  };

  # Surface HID keyboard (09AE) and touchpad (09AF) are separate product IDs, so
  # libinput does not treat them as one physical unit and disable-while-typing
  # stays off. Mark both internal.
  environment.etc."libinput/local-overrides.quirks".text = ''
    [Surface Laptop 3 Keyboard]
    MatchName=Microsoft Surface 045E:09AE
    AttrKeyboardIntegration=internal

    [Surface Laptop 3 Touchpad]
    MatchName=Microsoft Surface 045E:09AF Touchpad
    AttrKeyboardIntegration=internal
    AttrPalmSizeThreshold=800
  '';

  services.libinput.touchpad = {
    disableWhileTyping = true;
    tapping = true;
    naturalScrolling = true;
  };

  # First install of this machine was 24.05 — never bump.
  system.stateVersion = "24.05";
}

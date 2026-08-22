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

  # GiGstreem's gateway has no DHCP-reservation UI. Pin the address the TV
  # already uses; the existing NM profile keeps the PSK (do not rewrite it
  # via ensureProfiles). Remove this oneshot when the wired LAN lands.
  systemd.services.hearth-gigstreem-static = {
    description = "Pin GiGstreem Wi-Fi to 172.16.141.38";
    wantedBy = ["multi-user.target"];
    after = ["NetworkManager.service"];
    wants = ["NetworkManager.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "hearth-gigstreem-static" ''
        set -euo pipefail
        nmcli=${pkgs.networkmanager}/bin/nmcli
        if ! "$nmcli" -t -f NAME connection show | grep -qx GiGstreem; then
          echo "GiGstreem NM profile missing; skip static pin" >&2
          exit 0
        fi
        method=$("$nmcli" -g ipv4.method connection show GiGstreem)
        addrs=$("$nmcli" -g ipv4.addresses connection show GiGstreem)
        if [ "$method" = manual ] && [ "$addrs" = "172.16.141.38/24" ]; then
          exit 0
        fi
        "$nmcli" connection modify GiGstreem \
          ipv4.method manual \
          ipv4.addresses 172.16.141.38/24 \
          ipv4.gateway 172.16.141.1 \
          ipv4.dns 172.16.141.1
        if "$nmcli" -t -f NAME connection show --active | grep -qx GiGstreem; then
          "$nmcli" connection up GiGstreem
        fi
      '';
    };
  };

  # First install of this machine was 24.05 — never bump.
  system.stateVersion = "24.05";
}

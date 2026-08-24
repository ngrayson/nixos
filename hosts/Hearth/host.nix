# Hearth (Surface Laptop 3) — hostname, surface kernel, media-host power, touchpad.
{
  lib,
  pkgs,
  ...
}: let
  lan = import ../../common/lan.nix;
  hearthCidr = lan.cidrFor "Hearth";
in {
  imports = [
    (import ../../common/nix-maintenance.nix {
      dates = "weekly";
      deleteOlderThan = "14d";
      configurationLimit = 5;
    })
  ];

  networking.hostName = "Hearth";

  # Patched linux-surface kernel (module wired in flake.nix).
  hardware.microsoft-surface.kernelVersion = "stable";
  # linux-surface 6.19.8 is built from source with no binary cache. This Ice Lake
  # machine already enumerates IPTS + the HID touchpad on mainline 6.18; use the
  # nixpkgs kernel until a remote or cached surface kernel is available.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  zramSwap.enable = true;
  zramSwap.memoryPercent = 25;

  # Media host: lid-down is the normal pose. Never suspend on lid, even if
  # logind still thinks we are on battery (Surface ADP1 can lag the plug-in).
  services.logind.settings.Login = {
    HandleLidSwitch = lib.mkForce "ignore";
    HandleLidSwitchExternalPower = lib.mkForce "ignore";
    HandleLidSwitchDocked = lib.mkForce "ignore";
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

  # GiGstreem has no DHCP-reservation UI. Pin Hearth's current address so
  # the TV keeps reaching Jellyfin. PSK stays on the existing NM profile
  # (do not rewrite it via ensureProfiles). Address is common/lan.nix.
  systemd.services.hearth-gigstreem-static = {
    description = "Pin GiGstreem Wi-Fi to ${hearthCidr}";
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
        dns=$("$nmcli" -g ipv4.dns connection show GiGstreem)
        prio=$("$nmcli" -g connection.autoconnect-priority connection show GiGstreem)
        if [ "$method" = manual ] && [ "$addrs" = "${hearthCidr}" ] && [ "$dns" = "${lan.dns}" ] && [ "$prio" = "100" ]; then
          exit 0
        fi
        "$nmcli" connection modify GiGstreem \
          connection.autoconnect-priority 100 \
          ipv4.method manual \
          ipv4.addresses ${hearthCidr} \
          ipv4.gateway ${lan.gateway} \
          ipv4.dns "${lan.dns}"
        if "$nmcli" -t -f NAME connection show --active | grep -qx GiGstreem; then
          "$nmcli" connection up GiGstreem
        fi
      '';
    };
  };

  # Seagate IronWolf 4 TB (ST4000NE001) in a USB 3.2 UASP enclosure.
  # NTFS volume COLD — extant personal archive; do not format.
  # Layout on the volume: existing folders stay at the root; Jellyfin lives
  # under media/; seedbox + file-sharing under share/.
  boot.supportedFilesystems = ["ntfs"];
  fileSystems."/mnt/cold" = {
    device = "/dev/disk/by-uuid/22C21140C2111A1D";
    fsType = "ntfs";
    options = [
      "nofail"
      "x-systemd.device-timeout=10s"
      "uid=0"
      "gid=989" # jellyfin
      "umask=0002"
      "iocharset=utf8"
    ];
  };

  # Cursor CLI: `~/.local/bin/cursor-agent` (and `agent`) are vendor ELF shims
  # pointing at ~/.local/share/cursor-agent/versions/*/cursor-agent. They are
  # dynamically linked against FHS glibc, not Nix store paths. nix-ld provides
  # ld.so + a default lib set (same as Tawa/Theseus in profiles/workstation.nix).
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [];

  environment.systemPackages = [pkgs.code-cursor];

  # First install of this machine was 24.05 — never bump.
  system.stateVersion = "24.05";
}

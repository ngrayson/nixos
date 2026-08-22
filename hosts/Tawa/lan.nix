# Stable LAN identity for Tawa (Jellyfin host). Address lives in
# common/lan.nix so Hearth (and later hosts) cannot pin the same IPv4.
#
# AncientGlade is downstream (WAN .4, LAN 192.168.0.0/24); Wi-Fi clients
# reach this wired IP. Tawa's own Wi-Fi connection stays on DHCP.
{...}: let
  lan = import ../../common/lan.nix;
in {
  # Declarative NetworkManager profile; outranks the auto-generated DHCP
  # profile ("Wired connection 2") via autoconnect-priority.
  networking.networkmanager.ensureProfiles.profiles.wired-static = {
    connection = {
      id = "wired-static";
      type = "ethernet";
      interface-name = "enp5s0";
      autoconnect-priority = 10;
    };
    ipv4 = {
      method = "manual";
      # keyfile format: address1=IP/prefix,gateway
      address1 = lan.nmAddress1 "Tawa";
      dns = "${lan.dns};";
    };
    ipv6.method = "auto";
  };

  # mDNS: devices that support it (phones, laptops) can use tawa.local.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };
}

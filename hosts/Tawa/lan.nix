# Stable LAN identity for Tawa (Jellyfin host).
#
# Topology (discovered 2026-08): wired LAN is 172.16.141.0/24 (gw .1).
# The "AncientGlade" Wi-Fi router is downstream: its WAN is 172.16.141.4,
# its LAN is 192.168.0.0/24. Wi-Fi clients reach the wired net through it,
# so one static wired IP serves devices on both networks:
#   http://172.16.141.23:8096  (Jellyfin, works from wired and Wi-Fi)
# Tawa's own Wi-Fi connection stays on DHCP.
{...}: {
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
      address1 = "172.16.141.23/24,172.16.141.1";
      dns = "172.16.141.1;";
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

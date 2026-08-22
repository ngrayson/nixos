# Tawa is DHCP (wired + Wi-Fi). Jellyfin lives on Hearth; the old
# 172.16.141.23 pin is gone — see common/lan.nix.
{...}: {
  # mDNS: devices that support it can use tawa.local.
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

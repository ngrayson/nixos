# Single inventory of 172.16.141.0/24 static IPv4 assignments.
# Host modules import this — do not hardcode LAN addresses in host.nix.
#
# Topology (2026-08): GiGstreem LAN is 172.16.141.0/24 (gw .1). AncientGlade
# is a downstream Wi-Fi router (WAN .4, LAN 192.168.0.0/24). Tawa and Theseus
# stay on DHCP. Eval throws if any two names share an IP.
let
  prefix = 24;
  gateway = "172.16.141.1";
  # Public resolvers — ISP DNS plus Tailscale MagicDNS (accept-dns) hung
  # cache.nixos.org from Hearth on GiGstreem. Space-separated for nmcli ipv4.dns.
  dns = "1.1.1.1,8.8.8.8";

  hosts = {
    Hearth = "172.16.141.38";
  };

  reserved = {
    inherit gateway;
    ancientGladeWan = "172.16.141.4";
  };

  labeled = kind: set:
    map (n: {
      inherit n kind;
      ip = set.${n};
    }) (builtins.attrNames set);

  byIp = builtins.foldl' (
    acc: x:
      acc // {${x.ip} = (acc.${x.ip} or []) ++ [x];}
  ) {} (labeled "host" hosts ++ labeled "reserved" reserved);

  collisions = builtins.filter (ip: builtins.length byIp.${ip} > 1) (builtins.attrNames byIp);

  describe = ip:
    "${ip} used by ${
      builtins.concatStringsSep " and " (
        map (x: "${x.kind}:${x.n}") byIp.${ip}
      )
    }";
in
  if collisions != []
  then throw "LAN address collision in common/lan.nix: ${builtins.concatStringsSep "; " (map describe collisions)}"
  else {
    inherit prefix gateway dns hosts reserved;
    cidrFor = name: "${hosts.${name}}/${toString prefix}";
    nmAddress1 = name: "${hosts.${name}}/${toString prefix},${gateway}";
  }

# Tailnet-only reverse proxy for Jellyfin (plan.md H6). Not Funnel; not WAN.
# DNS: A tv.wizt.org → 100.84.222.78 (split-DNS wizt.org on the tailnet).
# TLS is Caddy's internal CA until a Tailscale/custom cert is issued.
{...}: let
  tailnetIPv4 = "100.84.222.78";
in {
  services.caddy = {
    enable = true;
    virtualHosts."tv.wizt.org" = {
      listenAddresses = ["${tailnetIPv4}:443"];
      extraConfig = ''
        reverse_proxy 127.0.0.1:8096
        tls internal
      '';
    };
  };

  systemd.services.caddy = {
    after = ["tailscaled.service" "jellyfin.service"];
    wants = ["tailscaled.service"];
  };
}

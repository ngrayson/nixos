# Tailnet-only reverse proxy for Jellyfin (plan.md H6). Not Funnel; not WAN.
# DNS: A tv.wizt.org → 100.84.222.78 (split-DNS wizt.org on the tailnet).
# TLS: Let's Encrypt via DNS-01 on Cloudflare (lego `cloudflare`).
# Operator: put CLOUDFLARE_DNS_API_TOKEN in secrets/acme-cloudflare.env
# (`sops secrets/acme-cloudflare.env`). The wizt.org zone must live at
# Cloudflare (free plan). Do not hearth-deploy until that token is real —
# Caddy waits on the ACME unit.
{
  config,
  ...
}: let
  tailnetIPv4 = "100.84.222.78";
in {
  sops.secrets.acme-cloudflare-env = {
    sopsFile = ../../secrets/acme-cloudflare.env;
    format = "dotenv";
    owner = "acme";
    group = "acme";
    mode = "0400";
  };

  security.acme = {
    acceptTerms = true;
    # Expiry notices only. Human mailbox stays in Bitwarden (H5).
    defaults.email = "acme@wizt.org";
    certs."tv.wizt.org" = {
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      environmentFile = config.sops.secrets.acme-cloudflare-env.path;
      group = "caddy";
      reloadServices = ["caddy.service"];
    };
  };

  services.caddy = {
    enable = true;
    virtualHosts."tv.wizt.org" = {
      listenAddresses = [tailnetIPv4];
      useACMEHost = "tv.wizt.org";
      extraConfig = ''
        reverse_proxy 127.0.0.1:8096
      '';
    };
  };

  systemd.services.caddy = {
    after = ["tailscaled.service" "jellyfin.service"];
    wants = ["tailscaled.service"];
  };
}

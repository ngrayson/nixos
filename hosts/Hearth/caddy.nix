# Tailnet-only reverse proxy for Jellyfin (plan.md H6). Not Funnel; not WAN.
# DNS: A tv.wizt.org → 100.84.222.78 (split-DNS wizt.org on the tailnet).
# TLS: Let's Encrypt via DNS-01 on Google Cloud DNS (lego `gcloud`).
# Operator: put a Cloud DNS Admin service-account JSON in
# secrets/acme-gce-sa.json (`sops secrets/acme-gce-sa.json`). The zone must
# be a GCP Cloud DNS zone, not Squarespace-only DNS. Do not deploy this
# host until that file is a real key — Caddy waits on the ACME unit.
{
  config,
  ...
}: let
  tailnetIPv4 = "100.84.222.78";
in {
  sops.secrets.acme-gce-sa = {
    sopsFile = ../../secrets/acme-gce-sa.json;
    format = "binary";
    owner = "acme";
    group = "acme";
    mode = "0400";
  };

  security.acme = {
    acceptTerms = true;
    # Expiry notices only. Human mailbox stays in Bitwarden (H5).
    defaults.email = "acme@wizt.org";
    certs."tv.wizt.org" = {
      dnsProvider = "gcloud";
      dnsResolver = "1.1.1.1:53";
      credentialFiles = {
        GCE_SERVICE_ACCOUNT_FILE = config.sops.secrets.acme-gce-sa.path;
      };
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

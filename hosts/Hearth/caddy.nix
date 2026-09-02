# Tailnet-only reverse proxy for Jellyfin (plan.md H6). Not Funnel; not WAN.
# DNS (operator, Cloudflare A → Hearth tailnet IPv4):
#   A tv.wizt.org → 100.84.222.78
#   A home.wizt.org → 100.84.222.78
# Split-DNS already forwards wizt.org on the tailnet. ACME (DNS-01) hangs
# Caddy if the Cloudflare name is missing — same constraint for both vhosts.
# TLS: Let's Encrypt via DNS-01 on Cloudflare (lego `cloudflare`).
# Operator: put CLOUDFLARE_DNS_API_TOKEN in secrets/acme-cloudflare.env
# (`sops secrets/acme-cloudflare.env`). The wizt.org zone must live at
# Cloudflare (free plan). Do not hearth-deploy until that token is real —
# Caddy waits on the ACME unit.
{
  config,
  pkgs,
  ...
}: let
  # Gitignored config.nix per widget (see intranet/config/default.nix).
  intranetCfg = import ./intranet/config;
  tailnetIPv4 = "100.84.222.78";
  # Same derivation flake.nix exposes as packages.x86_64-linux.hearth-intranet,
  # so a full switch and scripts/hearth-intranet-deploy.sh always agree.
  intranetRoot = import ./intranet-package.nix {inherit pkgs;};
  # Caddy serves the app off this persistent directory rather than off the
  # store path, so pushing a new dashboard build no longer rewrites the
  # Caddyfile — which is what made every CSS tweak cost a whole nixos-rebuild
  # switch. /var/lib and not /run: unlike the JSON widgets, which a timer
  # regenerates within a minute of boot, nothing would repopulate the site
  # itself after a reboot short of another switch.
  intranetServeDir = "/var/lib/hearth-intranet/current";
  hudHeaders = ''
    header {
      X-Content-Type-Options nosniff
      Referrer-Policy strict-origin-when-cross-origin
      Permissions-Policy "camera=(), microphone=(), geolocation=()"
      Strict-Transport-Security "max-age=31536000; includeSubDomains"
      X-Robots-Tag "noindex, nofollow"
      Content-Security-Policy "default-src 'self'; script-src 'self' https://maps.googleapis.com https://maps.gstatic.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: blob: https://maps.gstatic.com https://maps.googleapis.com https://*.googleapis.com https://*.gstatic.com; font-src 'self' https://fonts.gstatic.com; connect-src 'self' http://127.0.0.1:18090 https://api.open-meteo.com https://air-quality-api.open-meteo.com https://maps.googleapis.com https://maps.gstatic.com https://www.google.com; worker-src 'self' blob:; frame-src https://embed.waze.com; frame-ancestors 'self'; object-src 'none'; base-uri 'self'; form-action 'self'"
    }
  '';
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
    certs."home.wizt.org" = {
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
    virtualHosts."home.wizt.org" = {
      listenAddresses = [tailnetIPv4];
      useACMEHost = "home.wizt.org";
      extraConfig = ''
        ${hudHeaders}
        handle /status.json {
          root * /run/hearth-intranet
          file_server
        }
        handle /ingest.json {
          root * /run/hearth-intranet
          file_server
        }
        handle /transit.json {
          root * /run/hearth-intranet
          file_server
        }
        handle /aqi.json {
          root * /run/hearth-intranet
          file_server
        }
        handle /gallery.json {
          root * /run/hearth-intranet
          file_server
        }
        handle /calendar.ics {
          root * /run/hearth-intranet
          file_server
        }
        handle /maps-key.js {
          header Cache-Control "no-store"
          root * /run/hearth-intranet
          file_server
        }
        ${
          if (intranetCfg.gallery.galleryDir or "") != ""
          then ''
            handle_path /gallery/* {
              root * ${intranetCfg.gallery.galleryDir}
              file_server
            }
          ''
          else ""
        }
        root * ${intranetServeDir}
        file_server
      '';
    };
  };

  # The served directory outlives any one build, so it is created here rather
  # than by the sync unit: Caddy's `root *` points at it unconditionally, and a
  # missing root would turn every request into a 404 with no clue why.
  # hearth-deploy already puts the gitignored widget config.nix files in the
  # sibling `config/` for restic, so the parent is shared.
  systemd.tmpfiles.rules = [
    "d /var/lib/hearth-intranet 0755 root root -"
    "d ${intranetServeDir} 0755 root root -"
  ];

  # scripts/hearth-intranet-deploy.sh rsyncs into the directory above over SSH,
  # so rsync has to be on Hearth's system PATH and not only in the sync unit.
  # It is already pulled in incidentally today; declared here so the fast path
  # does not silently break if that changes.
  environment.systemPackages = [pkgs.rsync];

  # Keeps a real switch fully authoritative. ${intranetRoot} is interpolated
  # into the unit, so the unit's own text changes whenever the dashboard build
  # changes, and switch-to-configuration's normal unit diffing re-runs this on
  # exactly the switches where the app moved — no extra trigger needed. That is
  # also what erases any divergence left behind by a fast-path deploy: the
  # switch copies the declared build back over it.
  #
  # --delete so a file dropped from the build does not linger; --chmod because
  # store trees are read-only and rsync could not write into its own
  # destination on the next run.
  #
  # --checksum is load-bearing, not caution. Nix normalises every store file's
  # mtime to 1, so rsync's default size+mtime quick check sees no difference in
  # any file whose length happens to be unchanged and skips it. build-id.txt is
  # always exactly 65 bytes, so it was silently never updated — the one file the
  # kiosk polls to decide whether to reload. Observed 2026-09-02: a fast-path
  # deploy replaced the hashed asset bundles but left build-id.txt reading the
  # previous deploy's hash.
  systemd.services.hearth-intranet-sync = {
    description = "Sync the declared home.wizt.org build into ${intranetServeDir}";
    wantedBy = ["multi-user.target"];
    # A fresh boot must not let Caddy serve an empty directory.
    before = ["caddy.service"];
    # Deliberately no RemainAfterExit. A switch is only authoritative if it
    # re-syncs every time, and unit diffing alone does not do that: a fast-path
    # deploy of an uncommitted tweak leaves the declared build — and therefore
    # this unit's text — unchanged, so a subsequent switch would see nothing to
    # restart and the divergence would survive it. Left inactive after each run,
    # the unit is instead started on every activation.
    serviceConfig.Type = "oneshot";
    path = [pkgs.rsync];
    script = ''
      mkdir -p ${intranetServeDir}
      rsync -a --checksum --delete --chmod=D755,F644 ${intranetRoot}/ ${intranetServeDir}/
    '';
  };

  systemd.services.caddy = {
    after = ["tailscaled.service" "jellyfin.service"];
    wants = ["tailscaled.service"];

    # Both vhosts above bind tailnetIPv4 explicitly, which is deliberate —
    # home.wizt.org and tv.wizt.org are tailnet-only, and a wildcard bind would
    # widen that. The cost is that Caddy cannot start until tailscale0 actually
    # carries the address.
    #
    # `after = tailscaled.service` is not enough: tailscaled being *started* is
    # not the same as the interface having an address, and on a cold boot Caddy
    # wins that race and dies with
    #   listening on 100.84.222.78:80: bind: cannot assign requested address
    #
    # Nothing retries it, either. The upstream module sets Restart=on-failure
    # but also RestartPreventExitStatus=1, and Caddy exits 1 on a config-load
    # failure — sensible for a bad Caddyfile, wrong for a transient bind race.
    # Observed 2026-09-01: Hearth rebooted for the headless flip and the
    # dashboard stayed down until the unit was started by hand 93s later. It
    # had gone unnoticed for over eight days simply because the machine had not
    # rebooted in that time.
    #
    # So wait for the address rather than retrying the failure. Bounded, and
    # deliberately does not fail the unit on timeout: if the address never
    # appears, let Caddy start and produce its own clear error rather than
    # replacing it with a timeout nobody can interpret.
    preStart = ''
      for _ in $(seq 1 60); do
        if ${pkgs.iproute2}/bin/ip -4 addr show tailscale0 2>/dev/null \
          | grep -q "${tailnetIPv4}"; then
          exit 0
        fi
        sleep 1
      done
      echo "caddy: ${tailnetIPv4} did not appear on tailscale0 within 60s; starting anyway" >&2
    '';
  };
}

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
  lib,
  pkgs,
  ...
}: let
  lan = import ../../common/lan.nix;
  # Gitignored config.nix per widget (see intranet/config/default.nix).
  intranetCfg = import ./intranet/config;
  tailnetIPv4 = "100.84.222.78";
  intranetSrc = lib.fileset.toSource {
    root = ./intranet;
    fileset = lib.fileset.unions [
      ./intranet/package.json
      ./intranet/package-lock.json
      ./intranet/vite.config.js
      ./intranet/index.html
      ./intranet/src
      ./intranet/public
    ];
  };
  intranetApp = pkgs.buildNpmPackage {
    pname = "hearth-intranet";
    version = "0.0.1";
    src = intranetSrc;
    npmDepsHash = "sha256-3u4D8me9OiirC5dx91CWnL4sAviSFTZmiO6Bs1zTpg0=";
    npmBuildScript = "build";
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r dist/. "$out/"
      runHook postInstall
    '';
  };
  intranetPublic = {
    clock = intranetCfg.clock or {};
    weather = {
      locations = (intranetCfg.weather or {}).locations or [];
      temperatureUnit = (intranetCfg.weather or {}).temperatureUnit or "F";
    };
    transit = {
      busStops = (intranetCfg.transit or {}).busStops or [];
      mapQuery = (intranetCfg.transit or {}).mapQuery or "";
      mapZoom = (intranetCfg.transit or {}).mapZoom or 10;
      mapProvider = (intranetCfg.transit or {}).mapProvider or "waze";
    };
    health = intranetCfg.health or {};
    gallery = {};
    calendar = {};
  };
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
  intranetLanJs = pkgs.writeText "lan.js" ''
    window.hearthLan = "${lan.hosts.Hearth}";
  '';
  intranetCfgJs = pkgs.writeText "intranet-config.js" ''
    window.hearthIntranet = ${builtins.toJSON intranetPublic};
  '';
  # The dashboard's palette is picked in Settings from the same named schemes
  # the desktops use, so the hex values are generated from home/theme/schemes
  # rather than copied into the app. style.css's :root block still carries
  # Ghost's tokens as the pre-hydration fallback; everything after mount comes
  # from here, so editing a scheme reaches the page instead of drifting from
  # it. A scheme added to home/theme/schemes/default.nix shows up in the
  # picker with no JS change.
  intranetThemesJs = pkgs.writeText "themes.js" ''
    window.hearthThemes = ${
      builtins.toJSON (lib.mapAttrs (_: scheme: {inherit (scheme) name slug tokens;})
        (import ../../home/theme/schemes))
    };
  '';
  # Identifies the content Caddy is serving, so a long-lived tab can notice a
  # new deploy and reload itself — the kiosk loads this page once and never
  # navigates away, so nothing else would ever tell it.
  #
  # Covers the generated config and lan files as well as the built app: adding
  # a weather location changes what the running page holds in memory just as
  # much as a code change does, and the app derivation alone would miss it.
  #
  # Not a timestamp — a rebuild producing identical content leaves this
  # unchanged, so clients never reload for nothing. Hashed rather than served
  # as the store path itself, so a world-readable file does not publish
  # /nix/store paths.
  intranetBuildId = builtins.hashString "sha256" (
    toString intranetApp
    + toString intranetLanJs
    + toString intranetCfgJs
    + toString intranetThemesJs
  );
  intranetRoot =
    pkgs.runCommand "hearth-intranet" {
      lanJs = intranetLanJs;
      cfgJs = intranetCfgJs;
      themesJs = intranetThemesJs;
      nerdFont = "${pkgs.nerd-fonts.symbols-only}/share/fonts/truetype/NerdFonts/Symbols/SymbolsNerdFont-Regular.ttf";
      faviconSvg = ./intranet/favicon.svg;
      nativeBuildInputs = [pkgs.resvg pkgs.imagemagick];
    } ''
      mkdir -p "$out"
      cp -r ${intranetApp}/. "$out/"
      chmod -R u+w "$out"
      cp "$lanJs" "$out/lan.js"
      cp "$cfgJs" "$out/intranet-config.js"
      cp "$themesJs" "$out/themes.js"
      cp "$nerdFont" "$out/SymbolsNerdFont.ttf"
      cp "$faviconSvg" "$out/favicon.svg"
      resvg "$faviconSvg" "$out/favicon-32.png" -w 32 -h 32
      resvg "$faviconSvg" "$out/apple-touch-icon.png" -w 180 -h 180
      magick "$out/favicon-32.png" "$out/favicon.ico"
      # Polled by the dashboard; served by the same catch-all file_server as
      # everything else in here, so it needs no Caddy route of its own.
      echo "${intranetBuildId}" > "$out/build-id.txt"
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
        root * ${intranetRoot}
        file_server
      '';
    };
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

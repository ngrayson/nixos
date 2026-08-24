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
  # Only config.example.nix is imported. Sibling config.nix files are ignored.
  widgetNames = ["clock" "weather" "transit" "health" "gallery" "calendar"];
  intranetCfg = lib.listToAttrs (map (name: {
      inherit name;
      value = import (./intranet/config + "/${name}/config.example.nix");
    })
    widgetNames);
  tailnetIPv4 = "100.84.222.78";
  intranetRoot =
    pkgs.runCommand "hearth-intranet" {
      index = ./intranet/index.html;
      css = ./intranet/style.css;
      widgets = ./intranet/widgets.js;
      lanJs = pkgs.writeText "lan.js" ''
        window.hearthLan = "${lan.hosts.Hearth}";
      '';
      cfgJs = pkgs.writeText "intranet-config.js" ''
        window.hearthIntranet = ${builtins.toJSON intranetCfg};
      '';
      nerdFont = "${pkgs.nerd-fonts.symbols-only}/share/fonts/truetype/NerdFonts/Symbols/SymbolsNerdFont-Regular.ttf";
      faviconSvg = ./intranet/favicon.svg;
      nativeBuildInputs = [pkgs.resvg pkgs.imagemagick];
    } ''
      mkdir -p "$out"
      cp "$index" "$out/index.html"
      cp "$css" "$out/style.css"
      cp "$widgets" "$out/widgets.js"
      cp "$lanJs" "$out/lan.js"
      cp "$cfgJs" "$out/intranet-config.js"
      cp "$nerdFont" "$out/SymbolsNerdFont.ttf"
      cp "$faviconSvg" "$out/favicon.svg"
      resvg "$faviconSvg" "$out/favicon-32.png" -w 32 -h 32
      resvg "$faviconSvg" "$out/apple-touch-icon.png" -w 180 -h 180
      magick "$out/favicon-32.png" "$out/favicon.ico"
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
        handle /status.json {
          root * /run/hearth-intranet
          file_server
        }
        handle /transit.json {
          root * /run/hearth-intranet
          file_server
        }
        handle_path /gallery/* {
          root * ${intranetCfg.gallery.galleryDir}
          file_server browse
        }
        root * ${intranetRoot}
        file_server
      '';
    };
  };

  systemd.services.caddy = {
    after = ["tailscaled.service" "jellyfin.service"];
    wants = ["tailscaled.service"];
  };
}

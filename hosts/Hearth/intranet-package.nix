# The home.wizt.org dashboard, built as a plain derivation.
#
# Lives outside caddy.nix so there is exactly one definition reachable from two
# directions: `nixosConfigurations.Hearth` (via caddy.nix, for a real switch)
# and `packages.x86_64-linux.hearth-intranet` (via flake.nix, for the fast
# path). Same file, same inputs, same store path — a fast-path deploy and a
# full switch can never produce different output for the same source tree,
# which is the whole reason the fast path is safe to have.
#
# Impure: intranet/config reads the gitignored per-widget config.nix through
# builtins.getEnv, so every caller needs --impure and NIXOS_DIR (or HOME) set.
# scripts/hearth-deploy.sh and scripts/hearth-intranet-deploy.sh both do.
{pkgs}: let
  lib = pkgs.lib;
  lan = import ../../common/lan.nix;
  # Gitignored config.nix per widget (see intranet/config/default.nix).
  intranetCfg = import ./intranet/config;
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
in
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
  ''

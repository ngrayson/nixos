# Resolves `home/theme/hosts.nix` + scheme packs into `config.theme`.
# Change appearance per machine in hosts.nix — not in Stylix/Qt/Kitty modules.
{
  lib,
  nixosConfig ? null,
  ...
}: let
  themeLib = import ./lib.nix {inherit lib;};
  hosts = import ./hosts.nix;
  schemes = {
    izar = import ./schemes/izar.nix;
    lilac-ash = import ./schemes/lilac-ash.nix;
  };
  hostName =
    if nixosConfig == null
    then "Theseus"
    else nixosConfig.networking.hostName;
  host =
    hosts.${hostName}
    or (throw "theme: add ${hostName} to home/theme/hosts.nix");
  scheme =
    schemes.${host.scheme}
    or (throw "theme: unknown scheme '${host.scheme}' for ${hostName}");
  str = lib.types.str;
in {
  imports = [./apps.nix];

  options.theme = {
    name = lib.mkOption {type = str;};
    slug = lib.mkOption {type = str;};
    polarity = lib.mkOption {type = str;};
    spanMonitors = lib.mkOption {type = lib.types.bool;};
    wallpaper = lib.mkOption {type = lib.types.path;};
    wallpaperName = lib.mkOption {type = str;};
    obsidianVault = lib.mkOption {type = str;};
    tokens = lib.mkOption {type = lib.types.attrsOf str;};
    base16 = lib.mkOption {type = lib.types.attrsOf str;};
    kitty = lib.mkOption {type = lib.types.attrsOf str;};
    hex = lib.mkOption {type = lib.types.attrsOf str;};
    rgb = lib.mkOption {type = lib.types.attrsOf str;};
  };

  config.theme = {
    inherit (scheme) name slug polarity tokens base16 kitty;
    inherit (host) wallpaper wallpaperName spanMonitors;
    obsidianVault = host.obsidianVault or "Documents/the study";
    hex = lib.mapAttrs (_: themeLib.withHash) scheme.tokens;
    rgb = lib.mapAttrs (_: themeLib.toRgbCsv) scheme.tokens;
  };
}

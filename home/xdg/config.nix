# Repo-backed `xdg.configFile` (quickshell, kitty, fastfetch, topgrade, monitors, Kvantum).
{
  config,
  lib,
  nixosConfig ? null,
  pkgs,
  ...
}: let
  hs = import ../hypr/scripts.nix {inherit config lib pkgs;};
  hx = import ../lib/host-xdg.nix {inherit lib nixosConfig pkgs;};
in {
  xdg.configFile =
    {
      # Link the whole fallback tree file-by-file (recursive) rather than
      # enumerating each entry, so it can never drift out of sync with the
      # bundle as components are added (see home/hypr/scripts.nix). recursive
      # keeps per-file symlinks — quickshell may drop its own state into this
      # dir — while force lets them clobber anything already present.
      "quickshell" = {
        source = hs.quickshellBundled;
        recursive = true;
        force = true;
      };
      "kitty/kitty.conf" = {
        source = ../../kitty/kitty.conf;
        force = true;
      };
      "fastfetch/config.jsonc" = {
        source = hx.fastfetchConfig;
        force = true;
      };
      "fastfetch/izar-tsp.gif" = {
        source = ../../fastfetch/izar-tsp.gif;
        force = true;
      };
      "topgrade.toml" = {
        source = ../../topgrade/topgrade.toml;
        force = true;
      };
      "ovpn" = {
        source = ../../vpn/ovpn;
        recursive = true;
        force = true;
      };
    }
    // hx.hyprMonitorsXdg
    // hx.kvantumConfigFiles;
}

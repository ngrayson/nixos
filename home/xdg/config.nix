# Repo-backed `xdg.configFile` (quickshell, kitty, fastfetch, topgrade, monitors, Kvantum).
{
  config,
  lib,
  nixosConfig ? null,
  pkgs,
  ...
}: let
  hs = import ../hypr/scripts.nix {inherit config lib pkgs;};
  hx = import ../lib/host-xdg.nix {inherit lib nixosConfig;};
in {
  xdg.configFile =
    {
      "quickshell/shell.qml" = {
        source = "${hs.quickshellBundled}/shell.qml";
        force = true;
      };
      "quickshell/LockContext.qml" = {
        source = "${hs.quickshellBundled}/LockContext.qml";
        force = true;
      };
      "quickshell/LockSurface.qml" = {
        source = "${hs.quickshellBundled}/LockSurface.qml";
        force = true;
      };
      "quickshell/pam/password.conf" = {
        source = "${hs.quickshellBundled}/pam/password.conf";
        force = true;
      };
      "kitty/lilac-ash.conf" = {
        source = ../../kitty/lilac-ash.conf;
        force = true;
      };
      "kitty/kitty.conf" = {
        source = ../../kitty/kitty.conf;
        force = true;
      };
      "fastfetch/config.jsonc" = {
        source = ../../fastfetch/config.jsonc;
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
    }
    // hx.hyprMonitorsXdg
    // hx.kvantumConfigFiles;
}

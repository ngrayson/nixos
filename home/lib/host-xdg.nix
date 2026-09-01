# Host-scoped Kvantum + Hypr monitor + fastfetch config (paths relative to repo root via ../../ from home/lib).
{
  lib,
  nixosConfig ? null,
  pkgs,
}: let
  kvantumDir =
    if nixosConfig == null
    then null
    else ../../kvantum + "/${nixosConfig.networking.hostName}";
  kvantumConfigFiles =
    if kvantumDir == null || !builtins.pathExists kvantumDir
    then {}
    else {
      "Kvantum/kvantum.kvconfig" = {
        source = kvantumDir + "/kvantum.kvconfig";
        force = true;
      };
      "Kvantum/KvArcDark#/KvArcDark#.kvconfig" = {
        source = kvantumDir + "/KvArcDark#/KvArcDark#.kvconfig";
        force = true;
      };
      "Kvantum/LilacAsh/LilacAsh.kvconfig" = {
        source = kvantumDir + "/LilacAsh/LilacAsh.kvconfig";
        force = true;
      };
      "Kvantum/LilacAsh/LilacAsh.svg" = {
        source = kvantumDir + "/LilacAsh/LilacAsh.svg";
        force = true;
      };
    };

  hyprMonitorsConf =
    if nixosConfig == null
    then null
    else let
      p = ../../hypr + "/${nixosConfig.networking.hostName}/monitors.conf";
    in
      if builtins.pathExists p
      then p
      else null;

  hyprMonitorsXdg =
    if hyprMonitorsConf == null
    then {}
    else {
      "hypr/monitors.conf" = {
        source = hyprMonitorsConf;
        force = true;
      };
    };

  # fastfetch runs one shared config, but a module for absent hardware is not silent:
  # `battery` prints "No batteries found" on desktops because display.showErrors is on.
  # Hosts therefore contribute their extra Hardware-section modules as a fragment that
  # replaces the `@hardware-extra@` marker; hosts without one just lose the marker line.
  fastfetchHardwareExtra =
    if nixosConfig == null
    then null
    else let
      p = ../../fastfetch + "/${nixosConfig.networking.hostName}/hardware-extra.jsonc";
    in
      if builtins.pathExists p
      then p
      else null;

  fastfetchConfig = pkgs.runCommand "fastfetch-config.jsonc" {} (
    if fastfetchHardwareExtra == null
    then ''
      sed '/@hardware-extra@/d' ${../../fastfetch/config.jsonc} > $out
    ''
    else ''
      sed -e '/@hardware-extra@/{' -e 'r ${fastfetchHardwareExtra}' -e 'd' -e '}' \
        ${../../fastfetch/config.jsonc} > $out
    ''
  );
in {
  inherit fastfetchConfig fastfetchHardwareExtra hyprMonitorsConf hyprMonitorsXdg kvantumConfigFiles;
}

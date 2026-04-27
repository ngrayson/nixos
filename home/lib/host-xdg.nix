# Host-scoped Kvantum + Hypr monitor config (paths relative to repo root via ../../ from home/lib).
{
  lib,
  nixosConfig ? null,
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
in {
  inherit hyprMonitorsConf hyprMonitorsXdg kvantumConfigFiles;
}

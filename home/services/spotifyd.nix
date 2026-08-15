# Spotify Connect daemon with MPRIS for the quickshell media pill.
# Enabled for every desktop host that imports home/default.nix (Theseus + Tawa).
#
# Auth is OAuth and cannot run unattended: once per machine after first deploy,
#   spotifyd authenticate
# then `systemctl --user restart spotifyd`. Credentials land in
# ~/.cache/spotifyd/oauth/ and persist across boots.
{
  config,
  lib,
  nixosConfig ? null,
  ...
}: let
  hostName =
    if nixosConfig != null
    then nixosConfig.networking.hostName
    else "spotifyd";
  cachePath = "${config.home.homeDirectory}/.cache/spotifyd";
in {
  services.spotifyd = {
    enable = true;
    settings.global = {
      device_name = hostName;
      device_type = "computer";
      backend = "pulseaudio";
      bitrate = 320;
      use_mpris = true;
      # Session bus (not system): required for Quickshell / playerctl to see the player.
      dbus_type = "session";
      disable_discovery = false;
      cache_path = cachePath;
    };
  };

  # HM's module WantedBy=default.target starts before PipeWire/Hyprland, which races
  # mDNS ("No such device") and leaves MPRIS unregistered until a manual restart.
  systemd.user.services.spotifyd = {
    Unit = {
      After = [
        "graphical-session.target"
        "pipewire-pulse.service"
      ];
      Wants = ["pipewire-pulse.service"];
      PartOf = ["graphical-session.target"];
    };
    Install.WantedBy = lib.mkForce ["graphical-session.target"];
  };
}

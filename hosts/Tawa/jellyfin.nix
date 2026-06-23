# Jellyfin media server (Tawa only). Web UI: http://<host>:8096
{...}: {
  systemd.tmpfiles.rules = [
    "d /srv/media 0775 jellyfin jellyfin -"
    "d /srv/media/movies 0775 jellyfin jellyfin -"
    "d /srv/media/tv 0775 jellyfin jellyfin -"
    "d /srv/media/music 0775 jellyfin jellyfin -"
  ];

  # Let wiz add files under /srv/media without sudo.
  users.users.wiz.extraGroups = ["jellyfin"];
  users.users.jellyfin.extraGroups = ["video" "render"];

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # NixOS 25.11 has no services.jellyfin.hardwareAcceleration; enable VA API in the web UI
  # (Dashboard → Playback → Transcoding). PrivateDevices is already false in the module.
}

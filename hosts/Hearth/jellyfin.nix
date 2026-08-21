# Jellyfin media server (Hearth). Web UI: http://hearth:8096
# Ice Lake i5-1035G7: intel-media-driver (iHD) for VAAPI transcoding.
# Enable VAAPI in Dashboard → Playback → Transcoding.
{pkgs, ...}: {
  systemd.tmpfiles.rules = [
    "d /srv/media 0775 jellyfin jellyfin -"
    "d /srv/media/movies 0775 jellyfin jellyfin -"
    "d /srv/media/tv 0775 jellyfin jellyfin -"
    "d /srv/media/music 0775 jellyfin jellyfin -"
  ];

  users.users.wiz.extraGroups = ["jellyfin"];
  users.users.jellyfin.extraGroups = ["video" "render"];

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      libva-vdpau-driver
      intel-compute-runtime
    ];
  };
}

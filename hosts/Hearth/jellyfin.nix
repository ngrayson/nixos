# Jellyfin media server (Hearth). Web UI: http://hearth:8096
# Ice Lake i5-1035G7: intel-media-driver (iHD) for VAAPI transcoding.
# Enable VAAPI in Dashboard → Playback → Transcoding.
#
# No subtitle knobs here on purpose: the 15-20s blank-caption delay at play
# start is on-demand extraction reading the whole container off COLD at USB2
# speed, not a Jellyfin setting. See plan.md H3 before adding one.
{pkgs, ...}: {
  systemd.tmpfiles.rules = [
    # HDD (COLD). Created only when /mnt/cold is mounted; nofail so a missing
    # disk does not fail tmpfiles. Existing archive folders are left alone.
    "d /mnt/cold/media 0775 jellyfin jellyfin -"
    "d /mnt/cold/media/movies 0775 jellyfin jellyfin -"
    "d /mnt/cold/media/tv 0775 jellyfin jellyfin -"
    "d /mnt/cold/media/music 0775 jellyfin jellyfin -"
    "d /mnt/cold/share 0775 wiz jellyfin -"
  ];

  users.users.wiz.extraGroups = ["jellyfin"];
  users.users.jellyfin.extraGroups = ["video" "render"];

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # BindsTo stops jellyfin when COLD unmounts. WantedBy the mount starts it
  # again on remount/replug. Keep the module's wantedBy = multi-user.target.
  systemd.services.jellyfin = {
    after = ["mnt-cold.mount"];
    bindsTo = ["mnt-cold.mount"];
    wantedBy = ["mnt-cold.mount"];
    unitConfig.RequiresMountsFor = ["/mnt/cold"];
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

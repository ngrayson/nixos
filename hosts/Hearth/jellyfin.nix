# Jellyfin media server (Hearth). Web UI: http://hearth:8096
# Ice Lake i5-1035G7: intel-media-driver (iHD) for VAAPI transcoding.
# Enable VAAPI in Dashboard → Playback → Transcoding.
#
# No subtitle knobs here on purpose: first-play caption delay is on-demand
# ffmpeg extract of embedded ASS/SRT (whole-container read off COLD). After
# the 2026-08-25 USB fix that is ~8s on a 1.4 GB episode and ~31s on a 5.8 GB
# movie — not a Dashboard setting. See plan.md H3 before adding a pre-extract
# unit; the investigation recommended no service.
{pkgs, ...}: {
  systemd.tmpfiles.rules = [
    # HDD (COLD). Created only when /mnt/cold is mounted; nofail so a missing
    # disk does not fail tmpfiles. Existing archive folders are left alone.
    # ntfs-3g mounts COLD case-sensitively: these names must match the on-disk
    # ones exactly, or tmpfiles builds an empty twin beside the real archive.
    # The library paths Jellyfin scans are server state, not these rules — see
    # plan.md H2 before assuming a rename here is the whole fix.
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

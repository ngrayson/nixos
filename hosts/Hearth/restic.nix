# Encrypted restic of Hearth mutable state. Library and /nix/store stay off
# this repo.
#
# The repo lives on Hearth's NVMe, root-only (0700), Nick's choice on
# 2026-10-23. It used to sit on COLD, which is NTFS mounted gid=jellyfin
# umask=0002: every repo file was group-writable, so a compromised Jellyfin
# (LAN-facing) or Syncthing could delete the only copy, and NTFS cannot give
# one folder tighter permissions. The trade-off, accepted knowingly: this
# copy dies with the NVMe. Off-box (Tawa/B2) is still the follow-on that
# covers that. Backups also no longer depend on COLD being mounted.
#
# Password: secrets/hearth-restic-password.yaml (`password:`), encrypted for
# Tawa+Theseus+Hearth age publics. Nick creates it in Bitwarden and encrypts
# locally (`sops secrets/hearth-restic-password.yaml`). Never print it.
# Until that file exists, this module only creates the intranet-config
# staging dir — the backup unit stays off so Hearth still evaluates.
{
  config,
  lib,
  pkgs,
  ...
}: let
  passwordFile = ../../secrets/hearth-restic-password.yaml;
  havePassword = builtins.pathExists passwordFile;
in {
  systemd.tmpfiles.rules = [
    "d /var/lib/hearth-intranet 0755 root root -"
    "d /var/lib/hearth-intranet/config 0750 root root -"
    "d /var/lib/restic-repo 0700 root root -"
  ];

  sops.secrets.hearth-restic-password = lib.mkIf havePassword {
    sopsFile = passwordFile;
    key = "password";
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.restic.backups.hearth = lib.mkIf havePassword {
    initialize = true;
    repository = "/var/lib/restic-repo/hearth";
    passwordFile = config.sops.secrets.hearth-restic-password.path;
    paths = [
      "/var/lib/jellyfin"
      "/var/lib/tailscale"
      "/var/lib/acme"
      "/var/lib/sops-nix/key.txt"
      "/var/lib/hearth-intranet/config"
    ];
    exclude = [
      "/var/lib/jellyfin/transcodes"
      "/var/lib/jellyfin/cache"
    ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
    ];
  };
}

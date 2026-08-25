# Encrypted restic of Hearth mutable state. Repo lives on COLD so an NVMe
# death is a restore, not a household rebuild. Library and /nix/store stay
# off this repo. Off-box (Tawa/B2) is a follow-on.
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
    repository = "/mnt/cold/backups/hearth-restic";
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
    backupPrepareCommand = ''
      ${pkgs.util-linux}/bin/mountpoint -q /mnt/cold || {
        echo "COLD is not mounted; skip restic (nofail disk)."
        exit 1
      }
    '';
  };

  systemd.services.restic-backups-hearth = lib.mkIf havePassword {
    after = ["mnt-cold.mount"];
    wants = ["mnt-cold.mount"];
    unitConfig.RequiresMountsFor = ["/mnt/cold"];
  };
}

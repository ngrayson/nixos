# Shared user and rundir for hearth-intranet-* oneshots.
{
  users.groups.hearth-intranet = {};
  users.users.hearth-intranet = {
    isSystemUser = true;
    group = "hearth-intranet";
  };

  # Group-writable, group jellyfin: hearth-ingest (ingest.nix) writes its
  # ledger here but must run as wiz:jellyfin to touch COLD at all, and an
  # atomic os.replace() renames *into* this directory, so file-level
  # permissions are not enough — the directory itself has to be writable.
  systemd.tmpfiles.rules = [
    "d /run/hearth-intranet 0775 hearth-intranet jellyfin -"
  ];
}

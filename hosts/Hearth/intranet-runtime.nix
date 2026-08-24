# Shared user and rundir for hearth-intranet-* oneshots.
{
  users.groups.hearth-intranet = {};
  users.users.hearth-intranet = {
    isSystemUser = true;
    group = "hearth-intranet";
  };

  systemd.tmpfiles.rules = [
    "d /run/hearth-intranet 0755 hearth-intranet hearth-intranet -"
  ];
}

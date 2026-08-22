# Workstation SSH alias for deploying to Hearth. Fragment only — does not
# take over ~/.ssh/config. `hearth-deploy` adds `Include config.d/hearth`
# on first run if it is missing.
#
# PATH shim lives here (not only a zsh alias) so the command works in any
# shell, including before the next Tawa Home Manager switch.
{
  home.file.".local/bin/hearth-deploy" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      exec bash "$HOME/.config/nixos/scripts/hearth-deploy.sh" "$@"
    '';
  };

  home.file.".ssh/config.d/hearth" = {
    text = ''
      Host hearth
        HostName hearth.tail6cd822.ts.net
        User wiz
        Port 22
        ControlMaster auto
        ControlPath ~/.ssh/cm-%r@%h:%p
        ControlPersist 10m
    '';
  };
}

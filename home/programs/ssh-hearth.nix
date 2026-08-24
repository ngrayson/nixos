# Workstation SSH alias for deploying to Hearth. Fragment lives in
# ~/.ssh/config.d/hearth. Tawa's handwritten ~/.ssh/config already Includes
# it (or has Host hearth). Theseus has no ~/.ssh/config yet, so HM writes a
# Theseus-only Include. HostName must match scripts/hearth-deploy.sh
# HEARTH_SSH_HOSTNAME (hearth.tail6cd822.ts.net). OpenSSH to sshd:22, not
# Tailscale SSH.
#
# PATH shim lives here (not only a zsh alias) so hearth-deploy works in any
# shell, including before the next Home Manager switch.
{
  lib,
  nixosConfig ? null,
  ...
}: let
  hostName =
    if nixosConfig == null
    then ""
    else nixosConfig.networking.hostName;
in {
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

  home.file.".ssh/config" = lib.mkIf (hostName == "Theseus") {
    text = ''
      Include config.d/hearth
    '';
  };
}

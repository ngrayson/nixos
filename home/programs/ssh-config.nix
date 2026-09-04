# Owns ~/.ssh/config on hosts that do not have a handwritten one.
#
# Single owner on purpose. The config.d/* fragments (ssh-hearth.nix,
# ssh-go3.nix, ssh-tawa.nix) each write their own file, but only one module
# may write ~/.ssh/config itself -- two would collide at activation. This is
# that module.
#
# `Include config.d/*` rather than naming each fragment: the set differs per
# host (Hearth gets only ssh-tawa.nix, workstations get all three), and
# OpenSSH is happy with a glob that matches nothing.
{
  lib,
  nixosConfig ? null,
  ...
}: let
  hostName =
    if nixosConfig == null
    then ""
    else nixosConfig.networking.hostName;
  # Tawa's ~/.ssh/config is handwritten and predates this module -- it carries
  # hearth-lan / hearth-sshd entries that are not reproduced here. Do not
  # clobber it; Home Manager would move it aside to .hm-backup and silently
  # change how `ssh hearth` resolves.
  wantsManagedConfig = hostName == "Hearth" || hostName == "Theseus";
in {
  home.file.".ssh/config" = lib.mkIf wantsManagedConfig {
    text = ''
      # Include must precede every Host block: an Include placed after a Host
      # keyword belongs to that block and only applies when it matches.
      Include config.d/*
    '';
  };
}

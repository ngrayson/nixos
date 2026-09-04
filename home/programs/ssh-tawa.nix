# `ssh Tawa` from the recovery origins. Fragment lives in ~/.ssh/config.d/tawa;
# home/programs/ssh-config.nix writes the ~/.ssh/config that Includes it.
#
# Tailnet IP rather than MagicDNS, deliberately: Hearth and Go3 pass
# `--accept-dns=false` (see their remote-access.nix), so
# `tawa.tail6cd822.ts.net` does NOT resolve there -- verified 2026-09-03.
# A name that fails on the one always-on recovery origin is worse than an
# address that is stable as long as the node stays in the tailnet.
#
# Port 2222, not 22: common/tailscale.nix passes `--ssh`, so Tailscale SSH
# owns port 22 on Tawa's tailnet address and answers with an interactive
# browser check instead of key auth. hosts/Tawa/remote-access.nix adds 2222
# for exactly this reason.
{
  lib,
  nixosConfig ? null,
  ...
}: let
  hostName =
    if nixosConfig == null
    then ""
    else nixosConfig.networking.hostName;
  # Tawa needs no alias to itself, and writing one would only add a way to
  # loop back through sshd for no reason.
  wantsAlias = hostName == "Hearth" || hostName == "Theseus";
in {
  home.file.".ssh/config.d/tawa" = lib.mkIf wantsAlias {
    text = ''
      Host tawa Tawa
        HostName 100.96.243.48
        User wiz
        Port 2222
        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes
        # This is the lockout-recovery path, so fail fast and visibly rather
        # than hanging: a wedged Tawa should give an error, not a dead prompt.
        ConnectTimeout 10
        ServerAliveInterval 15
        ServerAliveCountMax 3
    '';
  };
}

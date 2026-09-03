# Workstation SSH alias for deploying to Hearth. Fragment lives in
# ~/.ssh/config.d/hearth. Tawa's handwritten ~/.ssh/config already Includes
# it (or has Host hearth). On hosts without a handwritten config,
# home/programs/ssh-config.nix writes one that Includes config.d/*. HostName must match scripts/hearth-deploy.sh
# HEARTH_SSH_HOSTNAME (hearth.tail6cd822.ts.net). OpenSSH to sshd:22, not
# Tailscale SSH.
#
# PATH shims live here (not only zsh aliases) so hearth-deploy and
# hearth-intranet-deploy work in any shell, including before the next Home
# Manager switch.
{...}: {
  home.file.".local/bin/hearth-deploy" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      exec bash "$HOME/.config/nixos/scripts/hearth-deploy.sh" "$@"
    '';
  };

  # Fast path for home.wizt.org only: builds .#hearth-intranet and rsyncs it
  # into /var/lib/hearth-intranet/current on Hearth. No nixos-rebuild, no Caddy
  # restart. hearth-deploy switch stays authoritative and re-syncs the declared
  # build over anything this pushed.
  home.file.".local/bin/hearth-intranet-deploy" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      exec bash "$HOME/.config/nixos/scripts/hearth-intranet-deploy.sh" "$@"
    '';
  };

  home.file.".ssh/config.d/hearth" = {
    text = ''
      # OpenSSH to sshd on GiGstreem (common/lan.nix Hearth pin). hearth-deploy
      # / nix-copy-closure need this, not Tailscale SSH on MagicDNS :22.
      Host hearth
        HostName 172.16.141.38
        User wiz
        Port 22
        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes
        ControlMaster auto
        ControlPath ~/.ssh/cm-%r@%h:%p
        ControlPersist 10m
        # ControlPersist keeps the control socket alive after the last session
        # closes, so a master whose TCP connection died silently (laptop
        # suspend, Wi-Fi roam) still accepts new sessions and then hangs them
        # with no data flowing. Without keepalive probes OpenSSH never notices,
        # and the caller's own timeout is the only thing that ever fires —
        # which is how hearth-tui hit a 15s TimeoutExpired mid-refresh. Three
        # missed 15s probes tear the dead master down instead.
        ServerAliveInterval 15
        ServerAliveCountMax 3

      # Tailscale SSH convenience (no key). Do not use for hearth-deploy.
      Host hearth-tailnet
        HostName hearth.tail6cd822.ts.net
        User wiz
        Port 22
    '';
  };
}

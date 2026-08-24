# sops-nix wiring for Tawa, Theseus, and Hearth. Gcp is deferred — do not
# import this from profiles/server.nix.
#
# Private age keys live in Bitwarden Pro. On each host, install that machine's
# key at /var/lib/sops-nix/key.txt (0400 root) before activate. See NEW-SYSTEM.md.
{
  inputs,
  pkgs,
  ...
}: {
  imports = [inputs.sops-nix.nixosModules.sops];

  sops = {
    defaultSopsFile = ../secrets/placeholder.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    # Age files only — do not fall back to the host SSH key.
    age.sshKeyPaths = [];
    # Dummy consumer so eval/activate exercise decrypt. Real secrets (Tailscale,
    # Discord, Restic, seedbox, Syncthing, git mailbox) wait until issued.
    secrets.placeholder = {};
  };

  environment.systemPackages = [pkgs.sops pkgs.age];
}

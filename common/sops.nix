# sops-nix wiring for Tawa, Theseus, and Hearth. Gcp is deferred — do not
# import this from profiles/server.nix.
#
# Private age keys live in Bitwarden Pro. On each host, install that machine's
# key at /var/lib/sops-nix/key.txt (0400 root) before activate. See NEW-SYSTEM.md.
{
  inputs,
  lib,
  pkgs,
  ...
}: let
  discordWebhook = ../secrets/hearth-discord-webhook.yaml;
in {
  imports = [inputs.sops-nix.nixosModules.sops];

  sops = {
    defaultSopsFile = ../secrets/placeholder.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    # Age files only — do not fall back to the host SSH key.
    age.sshKeyPaths = [];
    # Dummy consumer so eval/activate exercise decrypt. Real secrets (Tailscale,
    # Discord, Restic, seedbox, Syncthing, git mailbox) wait until issued.
    secrets.placeholder = {};
    # Hearthchime Incoming Webhook. Nick encrypts locally
    # (`sops secrets/hearth-discord-webhook.yaml`, key `url`). Never print it.
    # Until the file exists, this secret stays off so hosts still evaluate.
    secrets.hearth-discord-webhook = lib.mkIf (builtins.pathExists discordWebhook) {
      sopsFile = discordWebhook;
      key = "url";
      owner = "wiz";
      group = "users";
      mode = "0400";
    };
  };

  environment.systemPackages = [pkgs.sops pkgs.age];
}

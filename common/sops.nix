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
  calendarIcs = ../secrets/desktop-calendar-ics.yaml;
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
    # Google Calendar "secret iCal address"es (Calendar settings -> Integrate
    # calendar -> Secret address in iCal format) -- read-only .ics URLs. The
    # `url` value is ONE address per line (a YAML block scalar, `url: |`); the
    # sync script fetches and merges them all, so several calendars are added by
    # listing more lines. A single-line value still works. Nick encrypts locally
    # (`sops secrets/desktop-calendar-ics.yaml`, key `url`). The Quickshell
    # calendar popup's sync timer reads it (owner wiz, so the --user service
    # can). Until the file exists this stays off so hosts still evaluate; the
    # popup then shows the grid with an empty events list. Harmless on Hearth
    # (headless, no popup) -- the secret is simply unused.
    secrets.desktop-calendar-ics = lib.mkIf (builtins.pathExists calendarIcs) {
      sopsFile = calendarIcs;
      key = "url";
      owner = "wiz";
      group = "users";
      mode = "0400";
    };
  };

  environment.systemPackages = [pkgs.sops pkgs.age];
}

# Hearth remote access (H0). Written as a host-local module so it can move
# into profiles/media-server.nix at the H4 headless flip.
# SSH is key-only, matching profiles/server.nix. Extra client keys: append
# to users.users.wiz.openssh.authorizedKeys.keys (cat ~/.ssh/id_ed25519.pub
# on Go 2 / Tawa / Theseus).
# Tailscale is the shared module (same install as Tawa).
#
# trusted-users + passwordless wheel sudo let Tawa run `hearth-deploy`
# (nix-copy-closure as wiz, then --use-remote-sudo). Same sudo policy as
# profiles/server.nix; keep this host-local so Tawa/Theseus stay prompting.
{lib, ...}: {
  imports = [../../common/tailscale.nix];

  # MagicDNS as the only resolv.conf nameserver hung public lookups (nix
  # cache) on GiGstreem. Inbound tailnet SSH does not need accept-dns.
  services.tailscale.extraSetFlags = lib.mkForce ["--ssh" "--accept-dns=false"];
  networking.nameservers = ["1.1.1.1" "8.8.8.8"];

  users.users.wiz.openssh.authorizedKeys.keys = [
    # github.com/ngrayson.keys
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3Tk/SJjoGA1RR6NvGAQ+Lu7WZyuk3KydyhCiIldliZ"
    # Tawa builder (`~/.ssh/id_ed25519`, comment wiz@Tawa). Needed for
    # OpenSSH to sshd — Tailscale SSH is not enough for nix-copy-closure.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4FCRpTA4uD29z9zf6HTPDFVwZb1mAZ199kuRchqISx"
  ];

  services.openssh = {
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.tailscale.enable = true;

  networking.firewall = {
    allowedTCPPorts = [22];
    trustedInterfaces = ["tailscale0"];
  };

  nix.settings.trusted-users = ["@wheel"];
  security.sudo.wheelNeedsPassword = false;
}

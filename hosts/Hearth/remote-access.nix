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
    # Deliberately open on the LAN as well as the tailnet, so it is set
    # explicitly (openFirewall defaults to true, but the near-miss that
    # prompted this audit was relying on that default silently). Hearth now
    # lives on the ancientglade network, not the landlord-controlled GiGstreem
    # LAN, so a LAN-side port 22 is exposed only to Nick's own trusted network
    # — and it is the deploy escape hatch when the tailnet path is down (the
    # --ssh note above), unlike Go3 where the LAN path times out. This is the
    # only source of 22 now; the redundant `allowedTCPPorts = [22]` is gone.
    openFirewall = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.tailscale.enable = true;

  # No networking.firewall block: sshd opens its own port (above), and
  # trustedInterfaces is not re-declared here — common/tailscale.nix already
  # sets tailscale0, and repeating it produced a duplicate `tailscale0` entry.

  nix.settings.trusted-users = ["@wheel"];
  security.sudo.wheelNeedsPassword = false;
}

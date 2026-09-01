# Go3 remote access. SSH is key-only, matching profiles/server.nix and
# hosts/Hearth/remote-access.nix. Extra client keys: append to
# users.users.wiz.openssh.authorizedKeys.keys.
#
# trusted-users + passwordless wheel sudo let Tawa build and activate this
# host over SSH the same way hearth-deploy does (nix-copy-closure as wiz,
# then --use-remote-sudo). Keep it host-local so Tawa/Theseus keep prompting.
{lib, ...}: {
  imports = [../../common/tailscale.nix];

  # Same override as Hearth: MagicDNS as the only resolv.conf nameserver hung
  # public lookups (nix cache) on this LAN. Inbound tailnet SSH does not need
  # accept-dns.
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

  networking.firewall = {
    allowedTCPPorts = [22];
    trustedInterfaces = ["tailscale0"];
  };

  nix.settings.trusted-users = ["@wheel"];
  security.sudo.wheelNeedsPassword = false;
}

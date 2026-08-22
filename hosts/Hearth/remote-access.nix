# Hearth remote access (H0). Written as a host-local module so it can move
# into profiles/media-server.nix at the H4 headless flip.
# SSH is key-only, matching profiles/server.nix. Extra client keys: append
# to users.users.wiz.openssh.authorizedKeys.keys (cat ~/.ssh/id_ed25519.pub
# on Go 2 / Tawa / Theseus).
{
  users.users.wiz.openssh.authorizedKeys.keys = [
    # github.com/ngrayson.keys
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3Tk/SJjoGA1RR6NvGAQ+Lu7WZyuk3KydyhCiIldliZ"
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
}

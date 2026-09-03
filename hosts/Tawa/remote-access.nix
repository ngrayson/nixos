# Tawa inbound SSH. Exists so there is a dependable second way in when the
# desktop session is unusable -- a stuck session lock is the motivating case,
# since `qs-quickshell-ipc call lock activate` has no `deactivate` by design.
#
# Tailscale SSH (from ../../common/tailscale.nix, `--ssh`) already reaches this
# host and is the everyday path. It is NOT sufficient on its own here: it can
# demand an interactive browser re-auth at connect time ("Tailscale SSH
# requires an additional check"), which is exactly the wrong thing to hit while
# locked out. Key auth to sshd has no such step.
#
# Deliberately NOT copied from hosts/Hearth/remote-access.nix, which is a
# server:
#   - no `allowedTCPPorts = [22]`. common/tailscale.nix already makes
#     tailscale0 a trusted interface, so sshd is reachable over the tailnet
#     without opening port 22 to the apartment LAN.
#   - no passwordless wheel sudo. Hearth grants it so Tawa can drive
#     `hearth-deploy`; that file's own comment says to keep Tawa and Theseus
#     prompting, and this module does not change that.
{...}: {
  users.users.wiz.openssh.authorizedKeys.keys = [
    # github.com/ngrayson.keys -- same key Hearth and Go3 already trust.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3Tk/SJjoGA1RR6NvGAQ+Lu7WZyuk3KydyhCiIldliZ"
  ];

  services.openssh = {
    enable = true;
    # NOT the default. `openFirewall` defaults to true, which puts 22 in
    # networking.firewall.allowedTCPPorts on every interface -- verified, it
    # really does. common/tailscale.nix already trusts tailscale0, so leaving
    # the default would expose sshd to the apartment LAN for nothing, and that
    # LAN is behind a landlord-controlled AP rather than being ours alone.
    openFirewall = false;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}

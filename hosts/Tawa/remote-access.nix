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
    # Kept, but note it buys nothing for recovery: no machine on the tailnet
    # holds the private half. Verified 2026-09-03 -- neither Hearth nor
    # Theseus had any keypair at all, so this list was decorative.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3Tk/SJjoGA1RR6NvGAQ+Lu7WZyuk3KydyhCiIldliZ"
    # Hearth (`~/.ssh/id_ed25519`, SHA256:cHKzH8zbfQdy6Jzvu+66bZAiMeR7jBoPi+dBhXdm9Tc).
    # The primary recovery origin: headless, always on, already on the tailnet.
    # Passphraseless of necessity -- nobody is there to type one.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIOjx7IIs3uhZv34o241XtZ/utgHvvUpXnMqR8kMFUbe wiz@Hearth"
    # Theseus (`~/.ssh/id_ed25519`), the laptop. Second origin, for when the
    # problem is Hearth or the LAN. Passphrase-protected, which costs nothing
    # here: recovery from Theseus means sitting at Theseus anyway.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBc5SJzqyTToAwxcrK6fBhXuzstYtHALogtlzDfPOnEj wiz@Theseus"
  ];

  services.openssh = {
    enable = true;
    # NOT the default. `openFirewall` defaults to true, which puts 22 in
    # networking.firewall.allowedTCPPorts on every interface -- verified, it
    # really does. common/tailscale.nix already trusts tailscale0, so leaving
    # the default would expose sshd to the apartment LAN for nothing, and that
    # LAN is behind a landlord-controlled AP rather than being ours alone.
    openFirewall = false;
    # 2222 is what actually makes key auth reachable, and without it the whole
    # module is inert over the tailnet.
    #
    # common/tailscale.nix passes `--ssh`, so Tailscale SSH owns port 22 on
    # this host's tailnet address and answers before sshd ever sees the
    # connection. Combined with openFirewall = false -- which leaves 22 open
    # on tailscale0 and nowhere else -- the only interface where sshd is
    # reachable is precisely the one Tailscale SSH intercepts. Verified
    # 2026-09-03: both Theseus and Hearth got the interactive
    # "Tailscale SSH requires an additional check" browser prompt, never key
    # auth.
    #
    # Tailscale SSH intercepts 22 only, so a second port restores a real
    # key-authenticated path while keeping Tailscale SSH as the everyday one.
    # No firewall change is needed: trustedInterfaces already opens every port
    # on tailscale0.
    ports = [22 2222];
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}

# Workstation SSH alias for the Go3 kiosk. Fragment lives in
# ~/.ssh/config.d/go3; the handwritten ~/.ssh/config on Tawa must Include it
# (same bootstrap as config.d/hearth).
#
# Unlike Hearth there is no common/lan.nix static pin for this host — the
# kiosk is a Wi-Fi DHCP client — so MagicDNS is the address. This is OpenSSH
# to sshd:22 with a key (hosts/Go3/remote-access.nix), not Tailscale SSH;
# nix-copy-closure needs the real sshd.
{...}: {
  home.file.".ssh/config.d/go3" = {
    text = ''
      Host go3
        HostName go3.tail6cd822.ts.net
        User wiz
        Port 22
        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes
        ControlMaster auto
        ControlPath ~/.ssh/cm-%r@%h:%p
        ControlPersist 10m
        # Same rationale as config.d/hearth: ControlPersist keeps a master
        # alive after its TCP connection dies silently (Wi-Fi roam, suspend),
        # and without keepalives new sessions hang instead of failing.
        ServerAliveInterval 15
        ServerAliveCountMax 3
    '';
  };
}

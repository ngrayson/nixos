{
  inputs,
  pkgs,
  ...
}: let
  # Vortix is pinned to a known-good upstream revision in flake.lock.
  # Revision fbd3b43 (main, 2026-08-03) includes:
  #   - a0970ce fix(tui): disconnect completes on kernel confirmation, not the worker's word
  #     (fixes the disconnect->re-adopt->orphan loop that wedged connections; matches our field log)
  #   - 3e2767e fix(cli): lifecycle hardening — idempotent up, tracked-orphan filter, flock lock
  # Note: a0970ce is only on main, not in the v0.4.3 tag, so we pin the commit rather than the tag.
  vortixPackage = inputs.vortix.packages.${pkgs.system}.default;
  vpnFroot = pkgs.writeShellScriptBin "vpn-froot" ''
    set -euo pipefail

    if ! ${pkgs.systemd}/bin/systemctl is-active --quiet stunnel.service; then
      echo "stunnel.service is not active."
      echo "Run: sudo systemctl restart stunnel.service"
      exit 1
    fi

    exec ${pkgs.sudo}/bin/sudo ${vortixPackage}/bin/vortix "$@"
  '';
in {
  services.stunnel = {
    enable = true;
    clients.frootvpn = {
      accept = "127.0.0.1:1194";
      connect = "ca-west.frootvpn.com:443";
      CAFile = "/etc/frootvpn/stunnel-ca.pem";
      OCSPaia = false;
      verifyHostname = "server";
    };
  };

  environment.systemPackages = [
    pkgs.openvpn
    pkgs.curl
    pkgs.wireguard-tools
    pkgs.iptables
    pkgs.iproute2
    vortixPackage
    vpnFroot
  ];

  environment.etc."frootvpn/stunnel-ca.pem".source = ../frootvpn-stunnel-ca.pem;
}

{pkgs, ...}: let
  # Pin Vortix to a known-good upstream revision.
  vortixFlake = builtins.getFlake "github:Harry-kp/vortix/c1e142bb5983af043e5803944d2987e706421f2a";
  vortixPackage = vortixFlake.packages.${pkgs.system}.default;
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

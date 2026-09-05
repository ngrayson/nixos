# GCP-specific overrides. The imported NixOS GCE image module supplies the
# guest agent, image builder, disk growth, serial console, and network defaults.
{lib, ...}: {
  imports = [
    (import ../../common/nix-maintenance.nix {
      dates = "weekly";
      deleteOlderThan = "7d";
      configurationLimit = 3;
    })
  ];

  networking.hostName = "Gcp";

  # Keep the host firewall active even though the upstream GCE module defaults
  # to relying solely on VPC firewall rules.
  networking.firewall.enable = lib.mkForce true;

  # SSH hardening, staged for when this host is actually spun up (2026-09-05
  # network audit). Gcp is the only genuinely internet-facing host: it has a
  # public address and, unlike the LAN hosts, no `tailscale0` in
  # trustedInterfaces, so profiles/server.nix's `allowedTCPPorts = [22]` puts
  # sshd on the public interface. Two controls, in order of preference:
  #   1. Preferred once Gcp is on the tailnet: mirror Tawa — set
  #      `services.openssh.openFirewall = false`, drop 22 from
  #      allowedTCPPorts, and add `networking.firewall.trustedInterfaces =
  #      ["tailscale0"]` (import common/tailscale.nix). Do this ONLY after
  #      confirming the box is reachable over the tailnet, or you lock yourself
  #      out — there is no console to walk to.
  #   2. Until then the GCP VPC firewall is the real gate: narrow the SSH
  #      source range in scripts/gcp/create-instance.sh from 0.0.0.0/0 to a
  #      fixed admin CIDR (see README) rather than relying on the OS firewall.
  # sshd is already key-only (PasswordAuthentication/PermitRootLogin off in
  # profiles/server.nix), so this is defence in depth, not an open door.

  # The deployment script installs an `admin:` SSH key through instance
  # metadata. The guest agent manages that key and the google-sudoers group.
  security.googleOsLogin.enable = lib.mkForce false;

  virtualisation = {
    diskSize = 8192;
    googleComputeImage = {
      efi = true;
      compressionLevel = 6;
    };
  };

  system.stateVersion = "26.05";
}

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

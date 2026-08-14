# Minimal headless profile. Keep workstation, gaming, VPN, and Home Manager
# modules out of this file so cloud closures remain small.
{
  lib,
  pkgs,
  ...
}: {
  imports = [../common/base.nix];

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    vim
  ];

  users.users.admin = {
    isNormalUser = true;
    description = "Server administrator";
    extraGroups = ["wheel"];
    shell = pkgs.bashInteractive;
  };

  # Authentication is key-only. Cloud-specific modules must arrange the key
  # source (GCP metadata in hosts/Gcp).
  services.openssh = {
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [22];
  };

  security.sudo.wheelNeedsPassword = false;

  documentation.enable = false;
  programs.command-not-found.enable = false;

  system.stateVersion = lib.mkDefault "26.05";
}

# Headless media-server profile for Hearth. Not `profiles/server.nix` (that
# is Gcp/`admin`). Desktop rollback stays `profiles/media-desktop.nix`.
{pkgs, ...}: {
  imports = [
    ../common/base.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = false;

  security.polkit.enable = true;

  users.users.wiz = {
    isNormalUser = true;
    description = "Nick G";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.zsh;
  };
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-backup";
    users.wiz.imports = [../home/server.nix];
  };

  environment.systemPackages = with pkgs; [
    wget
    micro
    gh
    git
    btop
    fzf
    tree
    jq
    curl
  ];

  environment = {
    shells = [pkgs.zsh];
    variables.SHELL = "${pkgs.zsh}/bin/zsh";
    sessionVariables.SHELL = "${pkgs.zsh}/bin/zsh";
  };
}

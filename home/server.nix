# Slim Home Manager for headless Hearth: SSH shell only (plan.md H4).
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./programs/zsh.nix
    ./programs/git.nix
    # `ssh Tawa` from the always-on recovery origin. Hearth's slim HM does not
    # import home/default.nix, so these are wired explicitly rather than
    # inherited.
    ./programs/ssh-tawa.nix
    ./programs/ssh-config.nix
  ];

  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
  home.sessionPath = ["${config.home.homeDirectory}/.local/bin"];
  home.sessionVariables = {
    EDITOR = "${pkgs.micro}/bin/micro";
    SYSTEMD_EDITOR = "${pkgs.micro}/bin/micro";
    VISUAL = "${pkgs.micro}/bin/micro";
  };
  home.packages = with pkgs; [
    micro
    fastfetch
  ];
}

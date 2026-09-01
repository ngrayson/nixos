# Home Manager for the Go3 kiosk. Shell-only: the session itself is cage +
# Chromium from profiles/kiosk.nix, so there is no Hyprland, quickshell,
# stylix, dunst or launcher here. Kept separate from home/server.nix so
# Hearth's headless flip and the kiosk can diverge without touching Hearth.
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./programs/zsh.nix
    ./programs/git.nix
  ];

  # 25.11 matches home/server.nix and home/session.nix. Several modules under
  # home/programs/ branch on this staying pre-26.05; do not bump it casually.
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

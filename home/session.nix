# State version, HM CLI enable, session PATH/env, user-only packages.
{
  config,
  pkgs,
  ...
}: {
  home.stateVersion = "25.11";

  # `home-manager` command (news/tests); system activation is nixos-rebuild.
  programs.home-manager.enable = true;

  home.sessionPath = ["${config.home.homeDirectory}/.local/bin"];
  home.sessionVariables = {
    EDITOR = "${pkgs.micro}/bin/micro";
    SYSTEMD_EDITOR = "${pkgs.micro}/bin/micro";
    VISUAL = "${pkgs.micro}/bin/micro";
    TERMINAL = "${pkgs.kitty}/bin/kitty";
  };

  # Interactive user PATH (kitty stays in systemPackages for Plasma launchers).
  home.packages = with pkgs; [dunst fastfetch grim hyprmon jq newsboat quickshell slurp swaylock tmux tmuxifier wl-clipboard];
}

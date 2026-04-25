# Home Manager (user: wiz) — `home.username` / `home.homeDirectory` come from NixOS `users.users.wiz`
# Iterative migration: session env is HM-owned; next steps (git, kitty, zsh) move here over time.
{pkgs, ...}: {
  home.stateVersion = "25.11";

  # CLI: `home-manager` (useful for `home-manager news` and testing); system activation is via nixos-rebuild
  programs.home-manager.enable = true;

  # Was `environment.variables` + `environment.sessionVariables` in configuration.nix (user wiz only).
  home.sessionVariables = {
    EDITOR = "${pkgs.micro}/bin/micro";
    SYSTEMD_EDITOR = "${pkgs.micro}/bin/micro";
    VISUAL = "${pkgs.micro}/bin/micro";
    TERMINAL = "${pkgs.kitty}/bin/kitty";
    GIT_CONFIG_SYSTEM = "/run/current-system/etc/gitconfig";
  };

  # First user-only package proof (was environment.systemPackages); more can move later.
  home.packages = with pkgs; [fastfetch];
}

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

  # User-only packages (migrated from systemPackages over time; kitty here so HM owns the binary with config below)
  home.packages = with pkgs; [fastfetch kitty];

  # Kitty: sources live in this repo (./kitty/) — we use xdg, not programs.kitty, so HM does not generate a second kitty.conf
  # One-time: `force` overwrites files left by chezmoi; back up if you need the old copy
  xdg.configFile = {
    "kitty/lilac-ash.conf" = {
      source = ./kitty/lilac-ash.conf;
      force = true;
    };
    "kitty/kitty.conf" = {
      source = ./kitty/kitty.conf;
      force = true;
    };
  };
}

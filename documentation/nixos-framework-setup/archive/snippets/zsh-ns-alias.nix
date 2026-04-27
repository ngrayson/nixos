# Snippet: add `imports = [ ./snippets/zsh-ns-alias.nix ];` to configuration.nix,
# or merge the options below into an existing `programs.zsh` / `users` block.
{pkgs, ...}: {
  programs.zsh = {
    enable = true;
    shellAliases = {
      ns = "nix-search";
    };
  };

  users.users.wiz.shell = pkgs.zsh;
  users.defaultUserShell = pkgs.zsh;

  # systemd --user (and Plasma) may still export SHELL=bash; align system + session:
  environment.variables.SHELL = "${pkgs.zsh}/bin/zsh";
  environment.sessionVariables.SHELL = "${pkgs.zsh}/bin/zsh";
}
# For a user-level fallback before rebuild, you can add
# ~/.config/environment.d/99-zsh-shell.conf with: SHELL=/run/current-system/sw/bin/zsh


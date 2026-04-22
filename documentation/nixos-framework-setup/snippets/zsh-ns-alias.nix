# Add these lines inside your configuration.nix top-level attribute set
# (alongside programs.firefox, users.users.wiz, etc.).
# Merge into an existing programs.zsh block if you already have one.

programs.zsh = {
  enable = true;
  shellAliases = {
    ns = "nix-search";
  };
};

users.users.wiz.shell = pkgs.zsh;
users.defaultUserShell = pkgs.zsh;

# systemd --user (and Plasma) often still export SHELL=bash even when passwd
# says zsh. Fix both system-wide and session-wide:
environment.variables.SHELL = "${pkgs.zsh}/bin/zsh";
environment.sessionVariables.SHELL = "${pkgs.zsh}/bin/zsh";

# Optional user-level fallback (works even before rebuild): create
# ~/.config/environment.d/99-zsh-shell.conf with:
#   SHELL=/run/current-system/sw/bin/zsh

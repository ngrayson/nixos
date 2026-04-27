# Home Manager (user: wiz) — `home.username` / `home.homeDirectory` come from NixOS `users.users.wiz`
# Dotfiles: Home Manager only (no chezmoi).
# `nixosConfig` is set by the Home Manager NixOS module (NixOS `config`, for host-scoped options).
# Implementation: modular imports under `./home/` (start at `home/default.nix`).
{...}: {
  imports = [./home];
  # Wallust live theming: set `theme.dynamic = true` (disables Stylix Hyprland+GTK colors).
  theme.dynamic = true;
}

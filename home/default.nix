# Home Manager module bundle (imported from ../home.nix). Per-topic files live under this directory.
{...}: {
  imports = [
    ./stylix.nix
    ./session.nix
    ./programs/albert.nix
    ./programs/zsh.nix
    ./programs/git.nix
    ./wayland/hyprland.nix
    ./services/hypridle.nix
    ./activation/plasma-multi-monitor.nix
    ./xdg/config.nix
    ./xdg/data.nix
  ];
}

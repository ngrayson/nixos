# Slim Home Manager bundle for media-desktop hosts (Hearth).
# Omits slippi, spotifyd, photogimp, Plasma activation,
# and the workstation firefox rice. Albert stays (launcher). Hyprland /
# quickshell / stylix / zsh match Tawa/Theseus UX without the app pile.
{...}: {
  imports = [
    ./theme
    ./stylix.nix
    ./session.nix
    ./programs/qt-palette.nix
    ./programs/zsh.nix
    ./programs/git.nix
    ./programs/albert.nix
    ./wayland/hyprland.nix
    ./services/dunst.nix
    ./services/polkit-agent.nix
    ./services/hypridle.nix
    ./xdg/config.nix
    ./xdg/data.nix
    ./xdg/mime.nix
  ];
}

# Slim Home Manager bundle for media-desktop hosts (Hearth).
# Omits slippi, spotifyd, photogimp, qt-palette, Plasma activation,
# and the workstation firefox rice. Albert stays (launcher). Hyprland /
# quickshell / stylix / zsh match Tawa/Theseus UX without the app pile.
{pkgs, ...}: {
  imports = [
    ./theme
    ./stylix.nix
    ./session.nix
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

  # Same as Tawa/Theseus (`home/programs/qt-palette.nix`): Dolphin as the
  # file manager. MIME defaults in common/mime.nix point directories here.
  home.packages = [pkgs.kdePackages.dolphin];
}

# Home Manager module bundle (imported from ../home.nix). Per-topic files live under this directory.
{...}: {
  imports = [
    ./theme
    ./programs/photogimp.nix
    ./programs/firefox.nix
    ./stylix.nix
    ./services/rwpspread-wallpaper.nix
    ./session.nix
    ./programs/qt-palette.nix
    ./programs/albert.nix
    ./programs/slippi.nix
    ./programs/zsh.nix
    ./programs/git.nix
    ./wayland/hyprland.nix
    ./services/dunst.nix
    ./services/hypridle.nix
    ./services/spotifyd.nix
    ./activation/plasma-multi-monitor.nix
    ./xdg/config.nix
    ./xdg/data.nix
    ./xdg/mime.nix
    ./xdg/cursor-icon.nix
    ./gui-session-launch.nix
  ];
}

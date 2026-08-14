# State version, HM CLI enable, session PATH/env, user-only packages.
{
  config,
  pkgs,
  ...
}: {
  home.stateVersion = "25.11";

  # Mirrors `xdg.systemDirs.data` in `session.nix` — also set on Hypr's `env` so `exec-once` children
  # (`albert`, etc.) inherit Nix `.desktop` + icon theme lookups without sourced login shells.
  xdg.enable = true;
  xdg.systemDirs.data = [
    "${config.home.homeDirectory}/.local/share"
    "${config.home.profileDirectory}/share"
    "/run/current-system/sw/share"
  ];

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
  home.packages = with pkgs; [
    glib.bin # gsettings, gdbus — GTK/dconf checks (not on default NixOS PATH)
    # Screen color picker on Hyprland (compositor buffer; avoids gcolor3 / xdg_foreign on Wayland).
    # Super+Shift+C: see wayland/hyprland.nix (`hyprpicker -a -n` → wl-copy + dunst).
    hyprpicker
    dunst
    fastfetch
    (if pkgs ? crosspipe then pkgs.crosspipe else pkgs.helvum)
    hyprmon
    hyprshot
    jq
    newsboat
    nerd-fonts.iosevka-term-slab
    pamixer
    pavucontrol
    qpwgraph
    quickshell
    swaylock
    tmux
    tmuxifier
    wl-clipboard
  ];
}

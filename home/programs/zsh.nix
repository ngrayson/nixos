# Interactive zsh; NixOS `programs.zsh.enable` stays in `common/system.nix` for login PATH.
{
  config,
  lib,
  pkgs,
  ...
}: {
  # The oh-my-zsh `fzf` plugin below only needs the binary on PATH: its
  # `fzf_setup_using_fzf` branch runs first and does `eval "$(fzf --zsh)"` for
  # anything newer than 0.48. Nothing here installed it, so on hosts without a
  # broad package set (Go3's kiosk profile) the plugin printed
  # "Cannot find fzf installation directory" on every login. Workstations
  # masked it by pulling fzf in through profiles/workstation.nix.
  #
  # enableZshIntegration is off because the oh-my-zsh plugin already does that
  # exact eval — leaving it on sources the key bindings and completion twice.
  programs.fzf = {
    enable = true;
    enableZshIntegration = false;
  };

  programs.zsh = {
    enable = true;
    # Keep the pre-26.05 location while home.stateVersion remains 25.11.
    dotDir = config.home.homeDirectory;
    package = pkgs.zsh;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "clean";
      plugins = ["git" "history" "fzf" "node"];
    };
    initContent = lib.mkOrder 1500 ''
      # Replaces NixOS `programs.zsh.zsh-autoenv.enable`
      source ${pkgs.zsh-autoenv}/share/zsh-autoenv/autoenv.zsh
    '';
    shellAliases = {
      ns = "nix-search";
      vpn = "sudo vortix";
      vpn-froot = "vpn-froot";
      "agent-new" = "cd ~/Stellarium && claude";
      agent = "cd ~/Stellarium && claude --continue";
      config = "code ~/.config/nixos";
      fetch = "fastfetch";
      kitty = "kitty 2>/dev/null";
      l = "ls -CF";
      la = "ls -A";
      ll = "ls -ll";
      moon = "curl \"wttr.in/moon?Fun\"";
      notes = "obsidian";
      ohmyzshconfig = "micro ~/.config/nixos/home/programs/zsh.nix";
      "os-rebuild" = "bash ~/.config/nixos/documentation/nixos-framework-setup/os-rebuild.sh";
      "hearth-deploy" = "bash ~/.config/nixos/scripts/hearth-deploy.sh";
      "hearth-unmount" = "ssh hearth sudo hearth-disk park";
      stars = "astroterm -r 3 -Ccum -i seattle -s 50 -t 2.5 -l 1.7";
      termconfig = "micro ~/.config/nixos/kitty/kitty.conf";
      weather = "curl \"wttr.in/kirkland?FunQ2\"";
      "wifi-connect" = "nmcli device wifi connect";
      "wifi-connection" = "nmcli connection show";
      "wifi-list" = "nmcli device wifi list";
      zshconfig = "micro ~/.config/nixos/home/programs/zsh.nix";
      # Hyprland: edit `./hypr/<hostname>/monitors.conf` (hostname must match `networking.hostName`).
      hyprmon-cfg = "HYPRLAND_CONFIG=\"$HOME/.config/nixos/hypr/$(hostname)/monitors.conf\" ${lib.getExe pkgs.hyprmon}";
    };
  };
}

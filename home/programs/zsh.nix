# Interactive zsh; NixOS `programs.zsh.enable` stays in `common/system.nix` for login PATH.
{
  lib,
  pkgs,
  ...
}: {
  programs.zsh = {
    enable = true;
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
      "agent-new" = "cd ~/Stellarium && ~/.local/bin/cursor-agent";
      agent = "cd ~/Stellarium && ~/.local/bin/cursor-agent --resume";
      clock = "~/.cargo/bin/tenki --mode snow -l 1000 --wind disable";
      config = "code ~/.config/nixos";
      fetch = "fastfetch";
      gimp = "~/Apps/GIMP &";
      keyboard-flash = "sudo sleep 1; cd ~/pocket-reform/pocket-reform-keyboard-fw/pocket-hid; ./build.sh;echo \"flashing in 10s\";sleep 7; echo \"flashing in 3s\"; sleep 4;sudo picotool load build/pocket-hid.uf2 -f";
      kitty = "kitty 2>/dev/null";
      l = "ls -CF";
      la = "ls -A";
      ll = "ls -ll";
      moon = "curl \"wttr.in/moon?Fun\"";
      notes = "obsidian";
      obsidian = "~/Apps/Obsidian &";
      ohmyzshconfig = "micro ~/.config/nixos/home/default.nix";
      "os-rebuild" = "bash ~/.config/nixos/documentation/nixos-framework-setup/os-rebuild.sh";
      stars = "astroterm -r 3 -Ccum -i seattle -s 50 -t 2.5 -l 1.7";
      termconfig = "micro ~/.config/nixos/kitty/kitty.conf";
      weather = "curl \"wttr.in/kirkland?FunQ2\"";
      "wifi-connect" = "nmcli device wifi connect";
      "wifi-connection" = "nmcli connection show";
      "wifi-list" = "nmcli device wifi list";
      zshconfig = "micro ~/.config/nixos/home/default.nix";
      # Hyprland: edit `./hypr/<hostname>/monitors.conf` (hostname must match `networking.hostName`).
      hyprmon-cfg = "HYPRLAND_CONFIG=\"$HOME/.config/nixos/hypr/$(hostname)/monitors.conf\" ${lib.getExe pkgs.hyprmon}";
    };
  };
}

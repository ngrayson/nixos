# Home Manager (user: wiz) — `home.username` / `home.homeDirectory` come from NixOS `users.users.wiz`
# Iterative migration: session env + core programs.*; next: optional `xdg.*`, chezmoi alignment.
{
  lib,
  pkgs,
  ...
}: {
  home.stateVersion = "25.11";

  # CLI: `home-manager` (useful for `home-manager news` and testing); system activation is via nixos-rebuild
  programs.home-manager.enable = true;

  # Migrated from NixOS `programs.zsh` in `configuration.nix` (NixOS no longer sets global zsh; HM owns `~/.zshrc`)
  # Chezmoi: add `.zshrc` and `.zshenv` to `.chezmoiignore` so `chezmoi apply` does not overwrite HM. First activation: see
  # `home-manager.backupFileExtension` in `configuration.nix` (existing files renamed with `.hm-backup` instead of clobber)
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
      "agent-new" = "cd ~/Stellarium && cursor agent";
      agent = "cd ~/Stellarium && cursor agent --resume";
      chezpush = "~/bin/chezpush.sh";
      clock = "~/.cargo/bin/tenki --mode snow -l 1000 --wind disable";
      config = "code ~/.local/share/chezmoi; chezmoi apply";
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
      ohmyzshconfig = "micro ~/.config/nixos/home.nix";
      "os-rebuild" = "bash ~/.config/nixos/documentation/nixos-framework-setup/os-rebuild.sh";
      stars = "astroterm -r 3 -Ccum -i seattle -s 50 -t 2.5 -l 1.7";
      termconfig = "micro ~/.config/nixos/kitty/kitty.conf";
      weather = "curl \"wttr.in/kirkland?FunQ2\"";
      "wifi-connect" = "nmcli device wifi connect";
      "wifi-connection" = "nmcli connection show";
      "wifi-list" = "nmcli device wifi list";
      zshconfig = "micro ~/.config/nixos/home.nix";
    };
  };

  # Migrated from NixOS `programs.git` in `configuration.nix` (was `/etc/gitconfig` + `GIT_CONFIG_SYSTEM`)
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "wiz";
        email = "windows@example.com";
      };
      core = {
        editor = "micro";
        autocrlf = "input";
      };
      init.defaultBranch = "main";
      pull.rebase = false;
      push.default = "simple";
      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
        ci = "commit";
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
        visual = "!gitk";
      };
      credential = {
        "https://github.com".helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
        "https://gist.github.com".helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
      };
    };
  };

  # Was `environment.variables` + `environment.sessionVariables` in configuration.nix (user wiz only).
  home.sessionVariables = {
    EDITOR = "${pkgs.micro}/bin/micro";
    SYSTEMD_EDITOR = "${pkgs.micro}/bin/micro";
    VISUAL = "${pkgs.micro}/bin/micro";
    TERMINAL = "${pkgs.kitty}/bin/kitty";
  };

  # User-only packages (migrated from systemPackages over time)
  # kitty binary is in `environment.systemPackages` so Plasma shortcuts get it on the minimal system PATH; HM only owns config below
  home.packages = with pkgs; [fastfetch];

  # Kitty: sources live in this repo (./kitty/) — we use xdg, not programs.kitty, so HM does not generate a second kitty.conf
  # One-time: `force` overwrites files left by chezmoi; back up if you need the old copy
  xdg.configFile = {
    "kitty/lilac-ash.conf" = {
      source = ./kitty/lilac-ash.conf;
      force = true;
    };
    "kitty/kitty.conf" = {
      source = ./kitty/kitty.conf;
      force = true;
    };
  };
}

# Home Manager (user: wiz) — `home.username` / `home.homeDirectory` come from NixOS `users.users.wiz`
# Dotfiles: Home Manager only (no chezmoi).
{
  lib,
  pkgs,
  ...
}: let
  # `*.desktop` in ./desktop/applications/ → ~/.local/share/applications/ (see that folder’s README)
  appDir = ./desktop/applications;
  desktopDataFiles = lib.listToAttrs (
    map (n: {
      name = "applications/${n}";
      value = {
        source = appDir + "/${n}";
        force = true;
      };
    })
    (lib.attrNames (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".desktop" n) (builtins.readDir appDir)))
  );
in {
  home.stateVersion = "25.11";

  # CLI: `home-manager` (useful for `home-manager news` and testing); system activation is via nixos-rebuild
  programs.home-manager.enable = true;

  # Migrated from NixOS `programs.zsh` in `configuration.nix` (NixOS no longer sets global zsh; HM owns `~/.zshrc`)
  # First HM activation: see `home-manager.backupFileExtension` in `configuration.nix` if pre-existing `~/.zshrc` / `~/.zshenv` were renamed to `*.hm-backup`
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
      "agent-new" = "cd ~/Stellarium && ~/.local/bin/cursor agent";
      agent = "cd ~/Stellarium && ~/.local/bin/cursor agent --resume";
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

  # User-only CLIs (migrated from `environment.systemPackages` over time)
  # `kitty` stays in `systemPackages` so Plasma / minimal PATH sees it; these are for interactive user `PATH` only
  home.packages = with pkgs; [fastfetch newsboat tmux tmuxifier];

  # Kitty + fastfetch: sources in this repo — xdg, not `programs.kitty` / `programs.fastfetch`, so we do not get second generated configs
  # `force` overwrites pre-existing files under `~/.config/...` on activation; you can remove obsolete `~/.config/izar-tsp.gif` after first switch
  xdg.configFile = {
    "kitty/lilac-ash.conf" = {
      source = ./kitty/lilac-ash.conf;
      force = true;
    };
    "kitty/kitty.conf" = {
      source = ./kitty/kitty.conf;
      force = true;
    };
    "fastfetch/config.jsonc" = {
      source = ./fastfetch/config.jsonc;
      force = true;
    };
    "fastfetch/izar-tsp.gif" = {
      source = ./fastfetch/izar-tsp.gif;
      force = true;
    };
  };

  xdg.dataFile = desktopDataFiles;
}

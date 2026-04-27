# Home Manager (user: wiz) — `home.username` / `home.homeDirectory` come from NixOS `users.users.wiz`
# Dotfiles: Home Manager only (no chezmoi).
# `nixosConfig` is set by the Home Manager NixOS module (NixOS `config`, for host-scoped options).
{
  config,
  lib,
  nixosConfig ? null, # NixOS `config` from the Home Manager module (null only if not using the HM NixOS import)
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

  # Kvantum: `./kvantum/<hostname>/` (see kvantum/README.md) — same layout as ~/.config/Kvantum/
  kvantumDir =
    if nixosConfig == null
    then null
    else ./kvantum + "/${nixosConfig.networking.hostName}";
  kvantumConfigFiles =
    if kvantumDir == null || !builtins.pathExists kvantumDir
    then {}
    else {
      "Kvantum/kvantum.kvconfig" = {
        source = kvantumDir + "/kvantum.kvconfig";
        force = true;
      };
      "Kvantum/KvArcDark#/KvArcDark#.kvconfig" = {
        source = kvantumDir + "/KvArcDark#/KvArcDark#.kvconfig";
        force = true;
      };
      "Kvantum/LilacAsh/LilacAsh.kvconfig" = {
        source = kvantumDir + "/LilacAsh/LilacAsh.kvconfig";
        force = true;
      };
      "Kvantum/LilacAsh/LilacAsh.svg" = {
        source = kvantumDir + "/LilacAsh/LilacAsh.svg";
        force = true;
      };
    };
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

  # Hyprland: enable NixOS `programs.hyprland` in `common/system.nix` (session + portals).
  # `package` / `portalPackage` = null so the system module owns those packages.
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    systemd.enable = true;
    xwayland.enable = true;
    settings = {
      "$mod" = "SUPER";
      general = {
        gaps_in = 4;
        gaps_out = 8;
        border_size = 2;
      };
      decoration = {
        rounding = 8;
      };
      input = {
        kb_layout = "us";
        follow_mouse = 1;
      };
      bind =
        [
          "$mod, Return, exec, ${pkgs.kitty}/bin/kitty"
          "$mod, Q, killactive,"
          "$mod, M, exit,"
          "$mod, Space, exec, ${lib.getExe pkgs.albert} toggle"
          "$mod, L, exec, ${lib.getExe pkgs.swaylock}"
          "$mod, h, movefocus, l"
          "$mod, j, movefocus, d"
          "$mod, k, movefocus, u"
          "$mod, l, movefocus, r"
          "$mod SHIFT, h, movewindow, l"
          "$mod SHIFT, j, movewindow, d"
          "$mod SHIFT, k, movewindow, u"
          "$mod SHIFT, l, movewindow, r"
          "$mod, 1, workspace, 1"
          "$mod, 2, workspace, 2"
          "$mod, 3, workspace, 3"
          "$mod, 4, workspace, 4"
          "$mod, 5, workspace, 5"
          "$mod, 6, workspace, 6"
          "$mod, 7, workspace, 7"
          "$mod, 8, workspace, 8"
          "$mod, 9, workspace, 9"
          "$mod SHIFT, 1, movetoworkspace, 1"
          "$mod SHIFT, 2, movetoworkspace, 2"
          "$mod SHIFT, 3, movetoworkspace, 3"
          "$mod SHIFT, 4, movetoworkspace, 4"
          "$mod SHIFT, 5, movetoworkspace, 5"
          "$mod SHIFT, 6, movetoworkspace, 6"
          "$mod SHIFT, 7, movetoworkspace, 7"
          "$mod SHIFT, 8, movetoworkspace, 8"
          "$mod SHIFT, 9, movetoworkspace, 9"
          "$mod, mouse_down, workspace, e+1"
          "$mod, mouse_up, workspace, e-1"
        ]
        ++ [
          "$mod SHIFT, Space, togglefloating,"
          "$mod, F, fullscreen, 0"
        ];
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
      "exec-once" = [
        "${lib.getExe pkgs.dunst}"
        "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"
      ];
    };
    extraConfig = ''
      # Default workspaces per monitor (names from `hyprctl monitors`; edit if cabling changes).
      workspace = 1, monitor:DP-3
      workspace = 2, monitor:HDMI-A-1
      workspace = 3, monitor:DP-1
    '';
  };

  # Multi-monitor KWin prefs + Krohnkite option (Plasma session only).
  home.activation.plasmaMultiMonitor = lib.hm.dag.entryAfter ["writeBoundary"] ''
    kwrite="${pkgs.kdePackages.kconfig}/bin/kwriteconfig6"
    kwinrc="${config.home.homeDirectory}/.config/kwinrc"
    if [ -f "$kwinrc" ]; then
      $DRY_RUN_CMD "$kwrite" --file "$kwinrc" --group Windows --key SeparateScreenFocus --type bool true
      $DRY_RUN_CMD "$kwrite" --file "$kwinrc" --group TabBox --key MultiScreenMode --type int 2
      if $DRY_RUN_CMD grep -q '^\[Script-krohnkite\]' "$kwinrc"; then
        $DRY_RUN_CMD "$kwrite" --file "$kwinrc" --group Script-krohnkite --key layoutPerDesktop --type bool true
      fi
    fi
  '';

  # Was `environment.variables` + `environment.sessionVariables` in configuration.nix (user wiz only).
  home.sessionPath = ["${config.home.homeDirectory}/.local/bin"];
  home.sessionVariables = {
    EDITOR = "${pkgs.micro}/bin/micro";
    SYSTEMD_EDITOR = "${pkgs.micro}/bin/micro";
    VISUAL = "${pkgs.micro}/bin/micro";
    TERMINAL = "${pkgs.kitty}/bin/kitty";
  };

  # User-only CLIs (migrated from `environment.systemPackages` over time)
  # `kitty` stays in `systemPackages` so Plasma / minimal PATH sees it; these are for interactive user `PATH` only
  home.packages = with pkgs; [dunst fastfetch newsboat swaylock tmux tmuxifier wl-clipboard];

  # Kitty + fastfetch + Kvantum: sources in this repo — xdg, not `programs.kitty` / `programs.fastfetch`, so we do not get second generated configs
  # Kvantum: per-host under `./kvantum/<hostname>/` (theme + `kvantum.kvconfig`); `force` overwrites on activation
  xdg.configFile =
    {
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
      "topgrade.toml" = {
        source = ./topgrade/topgrade.toml;
        force = true;
      };
    }
    // kvantumConfigFiles;

  # Merge: ./desktop/applications/*.desktop plus kitty override (absolute Exec for Plasma shortcuts).
  xdg.dataFile =
    desktopDataFiles
    // {
      "applications/kitty.desktop" = {
        force = true;
        text = ''
          [Desktop Entry]
          Version=1.0
          Type=Application
          Name=kitty
          GenericName=Terminal emulator
          Comment=Fast, feature-rich, GPU based terminal
          TryExec=${pkgs.kitty}/bin/kitty
          StartupNotify=true
          Exec=${pkgs.kitty}/bin/kitty
          Icon=kitty
          Categories=System;TerminalEmulator;
          X-TerminalArgExec=--
          X-TerminalArgTitle=--title
          X-TerminalArgAppId=--class
          X-TerminalArgDir=--working-directory
          X-TerminalArgHold=--hold
        '';
      };
    };
}

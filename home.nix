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

  hyprScreenshotRegion = pkgs.writeShellScriptBin "hypr-screenshot-region" ''
    set -euo pipefail
    ${lib.getExe pkgs.grim} -g "$(${lib.getExe pkgs.slurp})" - | ${pkgs.wl-clipboard}/bin/wl-copy --type image
  '';
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
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = [
      {
        layer = "top";
        position = "top";
        height = 32;
        modules-left = ["hyprland/workspaces"];
        modules-center = ["clock"];
        modules-right = ["tray" "battery" "network" "pulseaudio"];
        "hyprland/workspaces" = {
          all-outputs = true;
        };
        clock = {
          format = "{:%a %d %b  %H:%M}";
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
        };
        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{capacity}% {icon}";
        };
        network = {
          format-wifi = "{essid} ({signalStrength}%) ";
          format-ethernet = "{ifname} ";
          format-disconnected = "—";
        };
        pulseaudio = {
          format = "{volume}% {icon}";
          format-muted = "muted";
        };
      }
    ];
  };

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
      # Session exit: Super+Shift+E (Super+M intentionally unbound per keybind pass).
      bind = [
        # --- Alt: navigation, workspaces, launcher ---
        "ALT, h, movefocus, l"
        "ALT, j, movefocus, d"
        "ALT, k, movefocus, u"
        "ALT, l, movefocus, r"
        "ALT SHIFT, h, movewindow, l"
        "ALT SHIFT, j, movewindow, d"
        "ALT SHIFT, k, movewindow, u"
        "ALT SHIFT, l, movewindow, r"
        "ALT, Return, exec, ${pkgs.kitty}/bin/kitty"
        "ALT, escape, killactive,"
        "ALT SHIFT, Q, killactive,"
        "ALT, Space, exec, ${lib.getExe pkgs.albert} toggle"
        "ALT, 1, workspace, 1"
        "ALT, 2, workspace, 2"
        "ALT, 3, workspace, 3"
        "ALT, 4, workspace, 4"
        "ALT, 5, workspace, 5"
        "ALT, 6, workspace, 6"
        "ALT SHIFT, 1, movetoworkspace, 1"
        "ALT SHIFT, 2, movetoworkspace, 2"
        "ALT SHIFT, 3, movetoworkspace, 3"
        "ALT SHIFT, 4, movetoworkspace, 4"
        "ALT SHIFT, 5, movetoworkspace, 5"
        "ALT SHIFT, 6, movetoworkspace, 6"
        # --- Super: layout, apps, session ---
        "$mod SHIFT, E, exit,"
        "$mod, F, fullscreen, 0"
        "$mod SHIFT, Space, togglefloating,"
        "$mod, Y, togglesplit"
        "$mod SHIFT, P, pseudo"
        "$mod SHIFT, S, exec, ${lib.getExe hyprScreenshotRegion}"
        "$mod, L, exec, ${lib.getExe pkgs.swaylock}"
        "$mod, B, exec, ${lib.getExe pkgs.firefox}"
        "$mod, D, exec, ${lib.getExe pkgs.discord}"
        "$mod, O, exec, ${lib.getExe pkgs.obsidian}"
        "$mod CTRL, h, resizeactive, -40 0"
        "$mod CTRL, j, resizeactive, 0 40"
        "$mod CTRL, k, resizeactive, 0 -40"
        "$mod CTRL, l, resizeactive, 40 0"
        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up, workspace, e-1"
        "$mod, bracketleft, workspace, m-1"
        "$mod, bracketright, workspace, m+1"
        "$mod, Tab, cyclenext"
        "$mod SHIFT, Tab, cyclenext, prev"
        ", Print, exec, ${lib.getExe hyprScreenshotRegion}"
      ];
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
      "exec-once" = [
        "${lib.getExe pkgs.albert}"
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
  home.packages = with pkgs; [dunst fastfetch grim newsboat slurp swaylock tmux tmuxifier wl-clipboard];

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

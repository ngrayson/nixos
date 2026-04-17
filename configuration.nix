# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  ...
}: let
  # Plymouth: single TTF via FreeType — Nerd Fonts much smaller than Iosevka (~13 MiB → ~2.4 MiB).
  # Heavy Data NF: smallest; fc-validate OK. Alternative: 3270 NFM Regular (~2.6 MiB, IBM terminal).
  #   plymouthNerdFontPkg = pkgs.nerd-fonts._3270;
  #   plymouthNerdFontRelPath = "share/fonts/truetype/NerdFonts/3270/3270NerdFontMono-Regular.ttf";
  plymouthNerdFontPkg = pkgs.nerd-fonts.heavy-data;
  plymouthNerdFontRelPath = "share/fonts/truetype/NerdFonts/HeavyData/HeavyDataNerdFont-Regular.ttf";
  plymouthNerdFontSrc = "${plymouthNerdFontPkg}/${plymouthNerdFontRelPath}";
  plymouthValidatedNerdFont =
    pkgs.runCommand "plymouth-nerd-font-validated" {
      nativeBuildInputs = [pkgs.fontconfig];
    } ''
      fc-validate "${plymouthNerdFontSrc}" || {
        echo "fc-validate failed: Plymouth font is not a valid fontconfig outline font"
        exit 1
      }
      install -Dm444 "${plymouthNerdFontSrc}" "$out/font.ttf"
    '';
in {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    <nixos-hardware/framework/13-inch/amd-ai-300-series>
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # AMD P-State active power management
  boot.kernelParams = ["amd_pstate=active"];

  # Graphical boot splash — Black HUD (adi1090x); Nerd Font face (see plymouthNerdFont* in let)
  boot.plymouth.enable = true;
  boot.plymouth.theme = "black_hud";
  boot.plymouth.themePackages = [
    (pkgs.adi1090x-plymouth-themes.override {selected_themes = ["black_hud"];})
  ];
  boot.plymouth.font = "${plymouthValidatedNerdFont}/font.ttf";

  # systemd in initrd: better Plymouth + LUKS ask-password integration than stage-1 script alone.
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."luks-61d676d2-6e31-41cd-a953-13d2bf0fd257".device = "/dev/disk/by-uuid/61d676d2-6e31-41cd-a953-13d2bf0fd257";
  networking.hostName = "Theseus"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Vancouver";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_CA.UTF-8";

  # Framework hardware support
  services.fprintd.enable = true;
  # If `fprintd-list-devices` shows nothing after rebuild, try Goodix TOD (common on Framework):
  # services.fprintd.tod.enable = true;
  # services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;

  # Fingerprint auth: not SDDM (password at cold login avoids long fprintd timeout before password).
  # TTY login, sudo, polkit, Plasma lock screen still use the reader — enroll after switch.
  # Keep your password working until enrollment succeeds (see NixOS wiki Fingerprint scanner).
  security.pam.services = {
    login.fprintAuth = true;
    sudo.fprintAuth = true;
    polkit-1.fprintAuth = true;
    kscreenlocker.fprintAuth = true;
  };

  security.polkit.enable = true;

  services.power-profiles-daemon.enable = true;
  services.fwupd.enable = true;
  powerManagement.enable = true;

  # Suspend / lid — explicit logind (Plasma + PPD: do not enable TLP; it fights power-profiles-daemon).
  # Investigation: projects/nixos-framework-setup/02-functional-improvements.md § Low-power suspend
  services.logind.settings = {
    Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
      HandleLidSwitchDocked = "ignore";
    };
  };

  # Bluetooth (BlueZ) — pairing via Plasma **Settings → Bluetooth**; audio via PipeWire below.
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # wireplumber.extraConfig.no-ucm = {
    # 	"monitor.alsa.properties" = {
    # 		"alsa.use-ucm" = false;
    # 	};
    # };

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Touchpad / pointing devices (explicit; matches checklist / Framework ergonomics).
  services.libinput.enable = true;

  # FrootVPN — Stunnel client: TLS to :443, OpenVPN sees 127.0.0.1:1194 (see localhost.ovpn).
  # CA PEM: extracted FrootVPN CA (same as in localhost.ovpn). Server TLS cert uses CN=server.
  # Change region: set connect to the hostname in another region’s *.conf (port stays 443).
  services.stunnel = {
    enable = true;
    clients.frootvpn = {
      accept = "127.0.0.1:1194";
      connect = "ca-west.frootvpn.com:443";
      # Installed readable by stunnel (runs as nobody); not under $HOME.
      CAFile = "/etc/frootvpn/stunnel-ca.pem";
      OCSPaia = false;
      verifyHostname = "server";
    };
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.wiz = {
    isNormalUser = true;
    description = "Nick G";
    extraGroups = ["networkmanager" "wheel"];
    packages = with pkgs; [
      kdePackages.kate
      #  thunderbird
    ];
  };

  # enable nix-command for nix seach
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Install firefox.
  programs.firefox.enable = true;

  # Git — system-wide /etc/gitconfig (replaces chezmoi ~/.gitconfig; see ~/.local/share/chezmoi/.chezmoiignore).
  programs.git = {
    enable = true;
    config = [
      {
        user = {
          name = "wiz";
          # Replace with your real address (was chezmoi `email`); same value is fine if you update chezmoi data for other hosts.
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
        credential."https://github.com".helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
        credential."https://gist.github.com".helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
      }
    ];
  };

  # Steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  # zshell
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    zsh-autoenv.enable = true;
    ohMyZsh = {
      enable = true;
      plugins = ["git" "history" "fzf" "node"];
      # Matches prior chezmoi ZSH_THEME; change in one place here, not ~/.zshrc
      theme = "clean";
    };
    shellAliases = {
      ns = "nix-search";
      vpn = "sudo vortix";
      # Merged from chezmoi dot_bash_aliases + dot_zshrc (see projects/nixos-framework-setup/08-dotfiles-migration-plan.md).
      # Complex or one-off aliases: adjust here deliberately (not bulk copy-paste).
      "agent-new" = "cd ~/Stellarium && cursor-agent";
      agent = "cd ~/Stellarium && cursor-agent --resume";
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
      ohmyzshconfig = "micro ~/.config/nixos/configuration.nix";
      stars = "astroterm -r 3 -Ccum -i seattle -s 50 -t 2.5 -l 1.7";
      termconfig = "chezmoi edit ~/.config/kitty/kitty.conf && chezmoi apply";
      weather = "curl \"wttr.in/kirkland?FunQ2\"";
      "wifi-connect" = "nmcli device wifi connect";
      "wifi-connection" = "nmcli connection show";
      "wifi-list" = "nmcli device wifi list";
      zshconfig = "chezmoi edit ~/.zshrc && chezmoi apply";
    };
  };

  users.users.wiz.shell = pkgs.zsh;
  users.defaultUserShell = pkgs.zsh;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add libs only if something still fails after rebuild (see below)
    # stdenv.cc.cc.lib
    # zlib
  ];

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    micro
    gh
    chezmoi
    btop
    bottom
    powertop
    fastfetch
    kitty
    alejandra
    fzf
    libnotify
    appimage-run
    topgrade
    kdePackages.kcolorchooser
    pkgs.albert
    # nix tools
    nix-search-cli

    # core tools
    openvpn
    # Vortix (https://github.com/Harry-kp/vortix) — TUI for OpenVPN/WireGuard; install UI: nix profile install github:Harry-kp/vortix
    curl
    wireguard-tools
    iptables
    iproute2
    pkgs.xd

    # apps
    libreoffice
    discord
    obsidian
    pkgs.spotify-qt
    pkgs.librespot
    pkgs.ungoogled-chromium

    # bitwarden
    bitwarden-desktop

    # tui
    glow
    chafa
    astroterm
    newsboat
    pkgs.tmux
    pkgs.tmuxifier
    tree

    # games
    pkgs.fuse # for slippi
    steam

    # dev
    pkgs.nodejs_20
    python3
    godot

    # ricing — Kvantum Qt style (Qt5 + Qt6; Plasma 6 needs Qt6)
    libsForQt5.qtstyleplugin-kvantum
    qt6Packages.qtstyleplugin-kvantum

    # for gtk theme
    sassc
    gnome-themes-extra
    gtk-engine-murrine
    tokyonight-gtk-theme
  ];

  environment = {
    shells = [pkgs.zsh];
    etc."frootvpn/stunnel-ca.pem".source = ./frootvpn-stunnel-ca.pem;
    # sessionVariables: Plasma / graphical apps; store paths: reliable when PATH is thin.
    variables = {
      EDITOR = "${pkgs.micro}/bin/micro";
      SYSTEMD_EDITOR = "${pkgs.micro}/bin/micro";
      VISUAL = "${pkgs.micro}/bin/micro";
    };
    sessionVariables = {
      EDITOR = "${pkgs.micro}/bin/micro";
      SYSTEMD_EDITOR = "${pkgs.micro}/bin/micro";
      VISUAL = "${pkgs.micro}/bin/micro";
      # Default terminal for scripts / tmux helpers that respect $TERMINAL
      TERMINAL = "${pkgs.kitty}/bin/kitty";
      # Git defaults to /etc/gitconfig; some shells/environments see /etc without that symlink.
      # Point at the generation-linked file so `git config --system` and `git config --list` match programs.git.
      GIT_CONFIG_SYSTEM = "/run/current-system/etc/gitconfig";
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}

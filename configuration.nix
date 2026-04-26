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

  # SDDM login background: image next to configuration.nix; Breeze theme with only background= patched.
  sddmLoginBg = builtins.path {
    path = ./login-bg.png;
    name = "login-bg.png";
  };
  sddmThemeBreezeLogin = pkgs.runCommand "sddm-theme-breeze-login" {} ''
    mkdir -p $out/share/sddm/themes
    cp -r ${pkgs.kdePackages.plasma-desktop}/share/sddm/themes/breeze $out/share/sddm/themes/breeze-login
    chmod -R u+w $out/share/sddm/themes/breeze-login
    sed -i "s|^background=.*|background=${sddmLoginBg}|" $out/share/sddm/themes/breeze-login/theme.conf
  '';

  # home-manager: release-25.11 matches NixOS 25.11; see ./home.nix and MIGRATION.md
  home-manager-src = builtins.fetchTarball {
    url = "https://github.com/nix-community/home-manager/archive/release-25.11.tar.gz";
    sha256 = "16mcnqpcgl3s2frq9if6vb8rpnfkmfxkz5kkkjwlf769wsqqg3i9";
  };
in {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    (import (home-manager-src + "/nixos"))
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

  # Fingerprint: SDDM uses `auth substack login` (see nixpkgs sddm module), so `login.fprintAuth`
  # gates graphical login too — not only `sddm.fprintAuth`. Keep login fingerprint off to avoid
  # the ~30s fprintd wait before password is accepted; sudo / polkit / lock screen still use the reader.
  # Keep your password working until enrollment succeeds (see NixOS wiki Fingerprint scanner).
  security.pam.services = {
    login.fprintAuth = false;
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
  services.displayManager.sddm.theme = "breeze-login";
  services.displayManager.sddm.settings.Theme = {
    CursorTheme = "breeze_cursors";
    CursorSize = 24;
  };
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

  # Declarative $HOME: activates with nixos-rebuild; `home.nix` for user "wiz" (see MIGRATION.md)
  home-manager = {
    useGlobalPkgs = true;
    # If HM-managed paths already exist (e.g. chezmoi `.zshrc`), first activation renames to `*.hm-backup` instead of failing
    backupFileExtension = "hm-backup";
    users.wiz = import ./home.nix;
  };

  # enable nix-command for nix seach
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Install firefox.
  programs.firefox.enable = true;

  # Steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  # zsh: `enable` must stay true on NixOS when the login shell is zsh (Nix store paths in /etc). Interactive bits live in home-manager ./home.nix
  programs.zsh.enable = true;
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
  environment.systemPackages =
    [sddmThemeBreezeLogin]
    ++ (with pkgs; [
      # vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
      wget
      micro
      gh
      chezmoi
      btop
      bottom
      powertop
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
      kitty
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
    ]);

  # User session env, programs.git, programs.zsh are in home-manager ./home.nix (user wiz).
  environment = {
    shells = [pkgs.zsh];
    etc."frootvpn/stunnel-ca.pem".source = ./frootvpn-stunnel-ca.pem;
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

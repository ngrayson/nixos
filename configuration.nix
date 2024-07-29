# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  ...
}: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  services.xserver = {
    layout = "us";
    xkbVariant = "";
    enable = true;

    desktopManager = {
      xterm.enable = false;
      plasma6.enable = true;
    };
    # windowManager.i3.enable = true;
    displayManager = {
      defaultSession = "plasma";
    };
  };

  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # xdg.portal.enable = true;
  # xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];
  hardware = {
    # Opengl
    # opengl.enable = true;
    # nvidia.modesetting.enable = true;
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable Bluetooth
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the default Bluetooth controller on boot

  # Enable polkit
  security.polkit.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.wiz = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "nick grayson";
    extraGroups = ["networkmanager" "wheel" "video"];
    packages = with pkgs; [
      kdePackages.kate
      #  thunderbird
    ];
  };

  users.defaultUserShell = pkgs.zsh;

  # enable zsh and oh my zsh
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    zsh-autoenv.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ll = "ls -l";
    };
    oh-my-zsh = {
      enable = true;
      theme = "jonathan";
      plugins = [
        "git"
        "npm"
        "history"
        "node"
        "deno"
      ];
    };
  };
  programs.thefuck.enable = true;
  # Install firefox.
  programs.firefox.enable = true;

  programs.steam.enable = true;

  environment = {
    shells = [pkgs.zsh];
    variables = {
      EDITOR = "micro";
      SYSTEMD_EDITOR = "micro";
      VISUAL = "micro";
    };
  };

  # enable hyprland
  #   programs.hyprland = {
  #     #  enable = true;
  #     #  xwayland.enable = true;
  #   };
  #
  #   xdg.portal.enable = true;
  #   xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];
  #   hardware = {
  #     # Opengl
  #     opengl.enable = true;
  #     nvidia.modesetting.enable = true;
  #   };

  # enable sway
  # programs.sway = {
  #   enable = true;
  #   wrapperFeatures.gtk = true;
  # };

  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    vscode
    discord
    obsidian
    bitwarden-desktop
    bottom
    neofetch
    git
    pkgs.nodejs_20
    pkgs.cbonsai
    gh
    libnotify
    alejandra
    micro
    peaclock

    # for pond
    gnumake
    gcc
    sqlite
    # python
    python3
    # temp

    # icons
    pkgs.beauty-line-icon-theme

    # trying to get i3 to work
    #     pkgs.libsForQt5.kconfig
    #     i3-gaps
    #
    #     i3
    #     pkgs.picom #anti-aliasing
    #     feh
    #     dmenu

    # pkgs.swayfx
    # grim # screenshot
    # slurp # screenshot
    # wl-clipboard # wl-copy and wl-paste

    ## hyprland packages
    wev
    #kitty
    # rofi-waylan
    # pkgs.dunst
    #pkgs.waybar
    #pkgs.networkmanager
    #pkgs.networkmanagerapplet
    #swww
    #alacritty
    brightnessctl
  ];

  # services.gnome.gnome-keyring.enable = true;

  fonts.packages = with pkgs; [
    (nerdfonts.override {fonts = ["FiraCode" "DroidSansMono" "Iosevka"];})
  ];

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
  system.stateVersion = "24.05"; # Did you read the comment?
}

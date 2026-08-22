# Slim Hyprland desktop for a media-host laptop. Imports only base.nix — not
# profiles/workstation.nix — so Steam, Slippi, VPN, Plasma, and the workstation
# package pile stay off this closure. Tawa/Theseus are unaffected.
{
  inputs,
  pkgs,
  ...
}: let
  sddmThemeBreezeLogin = import ../common/sddm-breeze-login.nix {inherit pkgs;};
  appimageRunWithCurl = import ../common/appimage-run-curl.nix {inherit pkgs;};
in {
  imports = [
    ../common/base.nix
    ../common/mime.nix
    ../common/albert-overlay.nix
  ];

  programs.dconf.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = false;
  # Secrets agent for nmgui / nmcli. AncientGlade's PSK is agent-owned;
  # without this, "Activate" fails with "No agents were available".
  programs.nm-applet.enable = true;
  programs.nm-applet.indicator = false;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

  security.polkit.enable = true;
  security.rtkit.enable = true;

  services.power-profiles-daemon.enable = true;
  # Plasma pulled this in on Tawa/Theseus. Without it, Quickshell's
  # UPower.displayDevice is empty and the battery pill stays hidden.
  services.upower.enable = true;
  powerManagement.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  hardware.graphics.enable = true;

  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = false;
  services.displayManager.sddm.theme = "breeze-login";
  # breeze-login is Plasma Breeze QML. plasma6.enable injects these into the
  # greeter wrap; Hearth does not enable Plasma, so list them here.
  services.displayManager.sddm.extraPackages = with pkgs.kdePackages; [
    breeze
    breeze-icons
    kirigami
    libplasma
    plasma-workspace
    plasma5support
    qt5compat
    qtsvg
    qtvirtualkeyboard
  ];
  services.displayManager.sddm.settings.Theme = {
    CursorTheme = "breeze_cursors";
    CursorSize = 24;
  };
  services.displayManager.defaultSession = "hyprland";

  programs.hyprland.enable = true;

  xdg.portal.config.common.default = ["hyprland" "gtk"];

  services.gvfs.enable = true;

  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  services.libinput.enable = true;

  fonts.packages = with pkgs; [
    nerd-fonts.iosevka-term-slab
  ];

  users.users.wiz = {
    isNormalUser = true;
    description = "Nick G";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.zsh;
    packages = with pkgs; [
      kdePackages.kate
    ];
  };
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {
      stylixModule = inputs.stylix.homeModules.stylix;
    };
    users.wiz.imports = [../home/media.nix];
  };

  programs.firefox.enable = true;

  programs.appimage = {
    enable = true;
    binfmt = true;
    package = appimageRunWithCurl;
  };

  environment.systemPackages =
    [sddmThemeBreezeLogin]
    ++ (with pkgs; [
      # Xcursor looks in the system profile; extraPackages only wrap QML.
      kdePackages.breeze
      adwaita-icon-theme
      wget
      micro
      gh
      git
      btop
      fzf
      tree
      libnotify
      alejandra
      nix-search-cli
      kitty
      brightnessctl
      vlc
      ffmpeg
      topgrade
      glow
      jq
      pkgs.albert
      appimageRunWithCurl
      pkgs.fuse
    ]);

  environment = {
    shells = [pkgs.zsh];
    variables.SHELL = "${pkgs.zsh}/bin/zsh";
    sessionVariables = {
      SHELL = "${pkgs.zsh}/bin/zsh";
      QT_QPA_PLATFORMTHEME = "kde";
      XDG_MENU_PREFIX = "plasma-";
    };
  };
}

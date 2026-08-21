# Slim Hyprland desktop for a media-host laptop. Imports only base.nix — not
# common/system.nix — so Steam, Slippi, VPN, Plasma, and the workstation
# package pile stay off this closure. Tawa/Theseus are unaffected.
{
  inputs,
  pkgs,
  unstablePkgs,
  ...
}: let
  sddmLoginBg = builtins.path {
    path = ../login-bg.png;
    name = "login-bg.png";
  };
  sddmThemeBreezeLogin = pkgs.runCommand "sddm-theme-breeze-login" {} ''
    mkdir -p $out/share/sddm/themes
    cp -r ${pkgs.kdePackages.plasma-desktop}/share/sddm/themes/breeze $out/share/sddm/themes/breeze-login
    chmod -R u+w $out/share/sddm/themes/breeze-login
    sed -i "s|^background=.*|background=${sddmLoginBg}|" $out/share/sddm/themes/breeze-login/theme.conf
  '';
  # Same override as common/system.nix (AppImages that need CURL_OPENSSL_4).
  appimageRunWithCurl = pkgs.appimage-run.override {
    extraPkgs = p: [p.curl];
  };
in {
  imports = [
    ../common/base.nix
    ../common/mime.nix
  ];

  # Albert: release NixOS pins an older Albert without the bundled Firefox
  # Python plugin. Unstable ships 34.x. Same overlay as common/system.nix.
  nixpkgs.overlays = [
    (final: prev: {
      albert = unstablePkgs.albert;
    })
  ];

  programs.dconf.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = false;

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

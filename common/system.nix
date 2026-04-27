# Shared NixOS module for all hosts. Per-machine: `hosts/<hostname>/` (hardware, host.nix, entry configuration.nix).
{
  config,
  pkgs,
  ...
}: let
  # Plymouth: single TTF via FreeType — Nerd Fonts much smaller than Iosevka (~13 MiB → ~2.4 MiB).
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

  # SDDM login background: repo root asset.
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

  # home-manager: release-25.11 matches NixOS 25.11; entry ../home.nix imports ./home/ — see MIGRATION.md
  home-manager-src = builtins.fetchTarball {
    url = "https://github.com/nix-community/home-manager/archive/release-25.11.tar.gz";
    sha256 = "16mcnqpcgl3s2frq9if6vb8rpnfkmfxkz5kkkjwlf769wsqqg3i9";
  };
in {
  imports = [
    (import (home-manager-src + "/nixos"))
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Graphical boot splash — Black HUD (adi1090x); Nerd Font face (see plymouthNerdFont* in let)
  boot.plymouth.enable = true;
  boot.plymouth.theme = "black_hud";
  boot.plymouth.themePackages = [
    (pkgs.adi1090x-plymouth-themes.override {selected_themes = ["black_hud"];})
  ];
  boot.plymouth.font = "${plymouthValidatedNerdFont}/font.ttf";

  # systemd in initrd: better Plymouth + LUKS ask-password integration than stage-1 script alone.
  boot.initrd.systemd.enable = true;

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Vancouver";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_CA.UTF-8";

  # Fingerprint: SDDM uses `auth substack login` (see nixpkgs sddm module), so `login.fprintAuth`
  # gates graphical login too — not only `sddm.fprintAuth`. Keep login fingerprint off to avoid
  # the ~30s fprintd wait before password is accepted; sudo / polkit / lock screen still use the reader.
  security.pam.services = {
    login.fprintAuth = false;
  };

  security.polkit.enable = true;

  services.power-profiles-daemon.enable = true;
  services.fwupd.enable = true;
  powerManagement.enable = true;

  services.logind.settings = {
    Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
      HandleLidSwitchDocked = "ignore";
    };
  };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  services.xserver.enable = true;

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.theme = "breeze-login";
  services.displayManager.sddm.settings.Theme = {
    CursorTheme = "breeze_cursors";
    CursorSize = 24;
  };
  services.desktopManager.plasma6.enable = true;
  # Hyprland (Wayland) default; KDE still available as plasma / plasmax11 at SDDM.
  programs.hyprland.enable = true;
  services.displayManager.defaultSession = "hyprland";

  # Prefer Hyprland for screencast/Wayland; GTK + KDE portals stay available (Plasma still installed).
  xdg.portal.config.common.default = ["hyprland" "gtk" "kde"];

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.printing.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.libinput.enable = true;

  services.stunnel = {
    enable = true;
    clients.frootvpn = {
      accept = "127.0.0.1:1194";
      connect = "ca-west.frootvpn.com:443";
      CAFile = "/etc/frootvpn/stunnel-ca.pem";
      OCSPaia = false;
      verifyHostname = "server";
    };
  };

  users.users.wiz = {
    isNormalUser = true;
    description = "Nick G";
    extraGroups = ["networkmanager" "wheel"];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };

  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-backup";
    users.wiz = import ../home.nix;
  };

  nix.settings.experimental-features = ["nix-command" "flakes"];

  programs.firefox.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  programs.zsh.enable = true;
  users.users.wiz.shell = pkgs.zsh;
  users.defaultUserShell = pkgs.zsh;

  nixpkgs.config.allowUnfree = true;

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [];

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  environment.systemPackages =
    [sddmThemeBreezeLogin]
    ++ (with pkgs; [
      wget
      micro
      gh
      btop
      bottom
      nautilus
      powertop
      alejandra
      hyprmon
      fzf
      libnotify
      appimage-run
      topgrade
      kdePackages.kcolorchooser
      pkgs.albert
      nix-search-cli
      openvpn
      curl
      wireguard-tools
      iptables
      iproute2
      pkgs.xd
      libreoffice
      discord
      obsidian
      pkgs.spotify-qt
      pkgs.librespot
      pkgs.ungoogled-chromium
      bitwarden-desktop
      glow
      chafa
      astroterm
      kitty
      tree
      pkgs.fuse
      steam
      pkgs.nodejs_20
      python3
      godot
      libsForQt5.qtstyleplugin-kvantum
      qt6Packages.qtstyleplugin-kvantum
      sassc
      gnome-themes-extra
      gtk-engine-murrine
      tokyonight-gtk-theme
    ]);

  environment = {
    shells = [pkgs.zsh];
    variables.SHELL = "${pkgs.zsh}/bin/zsh";
    sessionVariables.SHELL = "${pkgs.zsh}/bin/zsh";
    etc."frootvpn/stunnel-ca.pem".source = ../frootvpn-stunnel-ca.pem;
  };

  system.stateVersion = "25.11";
}

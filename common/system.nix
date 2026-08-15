# Shared NixOS module for all hosts. Per-machine: `hosts/<hostname>/` (hardware, host.nix, entry configuration.nix).
{
  config,
  inputs,
  pkgs,
  lib,
  unstablePkgs,
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

  # Flake inputs are pinned in flake.lock.
  slippi-nix-src = inputs.slippi-nix;

  # Slippi Dolphin AppImages prepend /usr/lib via linux-env.sh; default FHS libcurl
  # lacks CURL_OPENSSL_4. Shared by programs.appimage and environment.systemPackages.
  appimageRunWithCurl = pkgs.appimage-run.override {
    extraPkgs = p: [p.curl];
  };
in {
  imports = [
    ./base.nix
    # Slippi NixOS module: udev/runtime tuning for official GameCube USB adapter input.
    "${slippi-nix-src}/modules/nixos/gamecube-controller-adapter.nix"
    ./vpn-vortix.nix
  ];

  # Albert: release NixOS pins an older Albert without the bundled `firefox` Python plugin.
  # nixos-unstable ships Albert 34.x, which includes it (Python API 5.x). Only `albert` is taken from unstable.
  nixpkgs.overlays = [
    (final: prev: {
      albert = unstablePkgs.albert;
    })
  ];

  # Required for Stylix GTK theming via Home Manager (`gtk` target).
  programs.dconf.enable = true;

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

  # Make Nerd font families available system-wide so Qt/Quickshell can resolve icon glyphs.
  fonts.packages = with pkgs; [
    nerd-fonts.iosevka-term-slab
  ];

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
    extraSpecialArgs = {
      inherit slippi-nix-src;
      stylixModule = inputs.stylix.homeModules.stylix;
    };
    users.wiz = {
      imports = [
        ../home.nix
        "${slippi-nix-src}/modules/home-manager/default.nix"
      ];
    };
  };

  # Firefox: `ui.systemUsesDarkTheme=1` (NixOS `programs.firefox.preferences`) forces Gecko’s
  # built‑in dark chrome (e.g. tab strip ~#222D32), not Stylix GTK — tabs stay “wrong” vs Izar.
  # Leave unset so “System theme” follows GTK/Stylix (`headerbar_bg_color` / void from gtk.css).
  programs.firefox.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    # Inside Steam FHS so `gamescope … %command%` / `mangohud %command%` resolve (wiki / DeepWiki).
    extraPackages = with pkgs; [gamescope mangohud];
    extraCompatPackages = with pkgs; [proton-ge-bin];
  };

  programs.zsh.enable = true;
  users.users.wiz.shell = pkgs.zsh;
  users.defaultUserShell = pkgs.zsh;

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [];

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
      btop
      bottom
      feh
      nautilus
      powertop
      vlc
      pkgs.geeqie
      alejandra
      hyprmon
      fzf
      libnotify
      appimageRunWithCurl
      topgrade
      # Albert: from overlay (unstable); extensions — home/programs/albert.nix + ~/.config/albert/config.
      pkgs.albert
      pkgs.vscode
      pkgs.code-cursor
      nix-search-cli
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
      brave
      pkgs.blender
      pkgs.mendeley
      astroterm
      kitty
      tree
      pkgs.fuse
      pkgs.imagemagick
      pkgs.gimp-with-plugins
      pkgs.nodejs_22
      python3
      godot
      libsForQt5.qtstyleplugin-kvantum
      qt6Packages.qtstyleplugin-kvantum
      # pkgs.nwg-look
      sassc
      gnome-themes-extra
      gtk-engine-murrine
      pkgs.deluge-gtk
      pkgs.audacity
      pkgs.zip
      pkgs.ffmpeg
    ]);

  environment = {
    shells = [pkgs.zsh];
    variables.SHELL = "${pkgs.zsh}/bin/zsh";
    sessionVariables = {
      SHELL = "${pkgs.zsh}/bin/zsh";
      # Match HM qt platform theme (kde): Dolphin/KF6 need kde, not qt5ct.
      QT_QPA_PLATFORMTHEME = "kde";
    };
  };
}

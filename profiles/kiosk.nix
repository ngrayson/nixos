# Single-app Wayland kiosk profile (Go3). Imports only common/base.nix — not
# workstation.nix or media-desktop.nix — so SDDM, Plasma, Hyprland, Steam,
# VPN and the workstation package pile stay out of this closure.
#
# common/base.nix is four lines (locale, timezone, nix settings): it enables
# neither NetworkManager nor Bluetooth, so both are set explicitly here. Do
# not "fix" that by growing common/base.nix — it stays server-safe for Gcp.
{
  lib,
  pkgs,
  ...
}: let
  kioskUrl = "https://home.wizt.org";
  chromiumFlags = [
    "--kiosk"
    "--app=${kioskUrl}"
    "--ozone-platform=wayland"
    # Chromium gates its tap/scroll heuristics on this. Without it the Go 3
    # panel is treated as a hover-capable mouse and taps land wrong.
    "--touch-events=enabled"
    "--noerrdialogs"
    "--disable-infobars"
    "--no-first-run"
    "--disable-session-crashed-bubble"
    "--disable-features=TranslateUI"
  ];
in {
  imports = [
    ../common/base.nix
    ../common/tailscale.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = false;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  # No blueman: a cage session has no tray to put it in. Pair over Tailscale
  # SSH with `bluetoothctl`.

  hardware.graphics.enable = true;
  services.libinput.enable = true;

  security.polkit.enable = true;
  security.rtkit.enable = true;

  # cage runs exactly one Wayland client, fullscreen, on tty1 as `wiz`. That
  # is the entire session: no display manager, no compositor config, no bar,
  # and no way to escape the browser.
  services.cage = {
    enable = true;
    user = "wiz";
    program = "${lib.getExe pkgs.chromium} ${lib.concatStringsSep " " chromiumFlags}";
  };

  # Upstream's cage module sets restartIfChanged = false, so a switch tore the
  # kiosk down and left it down — the wall screen stayed blank until someone
  # SSHed in. (getty@tty1 takes tty1 the moment cage stops, because cage-tty1
  # Conflicts with it.) Nobody watches an appliance deploy, so a brief flicker
  # on every switch is strictly better than a silent dead screen.
  #
  # chvt 1 is the other half, and the reason a bare `systemctl start
  # cage-tty1` was never enough: logind grants DRM access on /dev/dri/* only
  # to seat0's ActiveSession, so cage exits ~10s after start whenever another
  # VT is active — exactly the state left behind once getty@tty1 has the
  # console. As ExecStartPre it makes every path (boot, deploy restart, manual
  # start) active-VT-correct, which is why no operator needs a separate
  # `sudo chvt 1` any more. Do not drop it: without it the ACL problem comes
  # straight back. The `+` prefix runs it as root — the unit body runs as
  # `wiz`, who cannot switch VTs.
  systemd.services.cage-tty1 = {
    restartIfChanged = lib.mkForce true;
    serviceConfig.ExecStartPre = "+${pkgs.kbd}/bin/chvt 1";
  };

  users.users.wiz = {
    isNormalUser = true;
    description = "Nick G";
    extraGroups = ["networkmanager" "wheel" "video" "input"];
    shell = pkgs.zsh;
  };
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-backup";
    users.wiz.imports = [../home/kiosk.nix];
  };

  environment.shells = [pkgs.zsh];
  environment.systemPackages = with pkgs; [
    chromium
    micro
    git
    btop
    wget
    jq
  ];
}

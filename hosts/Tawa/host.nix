# Tawa (desktop) — hostname, optional nixos-hardware, LUKS, kernelParams.
# Other hosts: add `hosts/<name>/host.nix` with their `networking.hostName` and imports.
{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./jellyfin.nix
    ./docker.nix
  ];

  networking.hostName = "Tawa";
  # Compatibility baseline from Tawa's original installation; do not bump with NixOS releases.
  system.stateVersion = "25.11";

  # Discrete AMD (RX 6700 class): explicit X / XWayland DDX; see NixOS Steam wiki / gaming guides.
  services.xserver.videoDrivers = ["amdgpu"];
  programs.gamemode.enable = true;

  # Plasma 6 sets SDDM to the Wayland greeter (KWin) by default. That path never runs
  # `services.xserver.displayManager.setupCommands`, so xrandr cannot shrink the login to one output.
  services.displayManager.sddm.wayland.enable = lib.mkForce false;

  # SDDM X11 greeter: turn off side outputs so Breeze only appears on the center panel.
  # Connector names must match `xrandr` (use a TTY/login session: `DISPLAY=:0 xrandr -q`).
  services.xserver.displayManager.setupCommands = lib.mkAfter ''
    XRANDR=${pkgs.xorg.xrandr}/bin/xrandr
    LOG=/tmp/sddm-xsetup-xrandr.log
    {
      echo "--- $(date)"
      "$XRANDR" --query || true
      QUERY="$("$XRANDR" --query 2>/dev/null)" || exit 0
      for o in DP-3 DP-1; do
        echo "$QUERY" | ${pkgs.gnugrep}/bin/grep -q "^$o connected" && "$XRANDR" --output "$o" --off || true
      done
      if echo "$QUERY" | ${pkgs.gnugrep}/bin/grep -q "^HDMI-A-1 connected"; then
        "$XRANDR" --output HDMI-A-1 --auto --primary || true
      fi
      echo "--- after ---"
      "$XRANDR" --query || true
    } >>"$LOG" 2>&1
  '';

  # boot.initrd.luks.devices."luks-…".device = "/dev/disk/by-uuid/…";
  # boot.kernelParams = ["amd_pstate=active"];
}

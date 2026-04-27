# Tawa (desktop) — hostname, optional nixos-hardware, LUKS, kernelParams.
# Other hosts: add `hosts/<name>/host.nix` with their `networking.hostName` and imports.
{
  pkgs,
  lib,
  ...
}: {
  imports = [
    # <nixos-hardware/framework/13-inch/amd-ai-300-series>
  ];

  networking.hostName = "Tawa";

  # SDDM uses the X11 greeter unless `services.displayManager.sddm.wayland.enable` is set.
  # Turn off side outputs so the Breeze greeter only appears on the center panel (names must
  # match `xrandr` / `hypr/Tawa/monitors.conf`).
  services.xserver.displayManager.setupCommands = lib.mkAfter ''
    XRANDR=${pkgs.xorg.xrandr}/bin/xrandr
    QUERY="$("$XRANDR" --query 2>/dev/null)" || exit 0
    for o in DP-3 DP-1; do
      echo "$QUERY" | ${pkgs.gnugrep}/bin/grep -q "^$o connected" && "$XRANDR" --output "$o" --off || true
    done
    if echo "$QUERY" | ${pkgs.gnugrep}/bin/grep -q "^HDMI-A-1 connected"; then
      "$XRANDR" --output HDMI-A-1 --auto --primary || true
    fi
  '';

  # boot.initrd.luks.devices."luks-…".device = "/dev/disk/by-uuid/…";
  # boot.kernelParams = ["amd_pstate=active"];
}

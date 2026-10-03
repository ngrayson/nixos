# OBS Studio — Tawa only, for screen recording.
# Screen capture on Hyprland uses OBS's built-in "Screen Capture (PipeWire)" source via
# xdg-desktop-portal-hyprland, so no wlrobs. No virtual camera: Nick only records, and
# enableVirtualCamera would add the v4l2loopback kernel module for nothing.
{pkgs, ...}: {
  programs.obs-studio = {
    enable = true;
    # Per-application audio sources (Application Audio Capture).
    plugins = [pkgs.obs-studio-plugins.obs-pipewire-audio-capture];
  };
}

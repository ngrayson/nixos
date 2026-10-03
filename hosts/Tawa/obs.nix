# OBS Studio — Tawa only.
# Screen capture on Hyprland uses OBS's built-in "Screen Capture (PipeWire)" source via
# xdg-desktop-portal-hyprland, so no wlrobs. The virtual camera is v4l2loopback, a kernel
# module loaded at boot: until the first reboot after enabling it, `sudo modprobe v4l2loopback`.
{pkgs, ...}: {
  programs.obs-studio = {
    enable = true;
    # OBS shows up as a webcam ("OBS Virtual Camera") in calls.
    enableVirtualCamera = true;
    # Per-application audio sources (Application Audio Capture).
    plugins = [pkgs.obs-studio-plugins.obs-pipewire-audio-capture];
  };
}

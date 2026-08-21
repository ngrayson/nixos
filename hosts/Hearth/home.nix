# Hearth-only Home Manager overrides. Imported from configuration.nix so the
# slim media-desktop profile stays reusable.
{
  lib,
  pkgs,
  config,
  ...
}: let
  hs = import ../../home/hypr/scripts.nix {inherit config lib pkgs;};
in {
  home-manager.users.wiz = {
    # Palm rejection / disable-while-typing on the Surface HID touchpad.
    wayland.windowManager.hyprland.settings.input.touchpad = {
      disable_while_typing = true;
      natural_scroll = true;
      tap-to-click = true;
      clickfinger_behavior = true;
    };

    # Media host: lock and DPMS on idle, but do not suspend (kills Jellyfin clients).
    services.hypridle.settings.listener = lib.mkForce [
      {
        timeout = 300;
        on-timeout = lib.getExe hs.quickshellLockGuarded;
      }
      {
        timeout = 600;
        on-timeout = lib.getExe hs.hyprDpmsAllOffGuarded;
        on-resume = lib.getExe hs.hyprDpmsAllOn;
      }
    ];
  };
}

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
    # nmgui (left-click network pill) uses Adwaita symbolic names, not nerd
    # fonts. Slim media-desktop has no Plasma icon theme on the GTK path.
    gtk.iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };

    # Palm rejection / disable-while-typing on the Surface HID touchpad.
    wayland.windowManager.hyprland.settings.input.touchpad = {
      disable_while_typing = true;
      natural_scroll = true;
      tap-to-click = true;
      clickfinger_behavior = true;
    };

    # Lid close blanks the panel only. logind stays ignore (no suspend), so
    # SSH and Jellyfin keep running. switch:on = closed on this Surface.
    wayland.windowManager.hyprland.settings.bindl = [
      ", switch:on:Lid Switch, exec, ${lib.getExe hs.hyprDpmsAllOff}"
      ", switch:off:Lid Switch, exec, ${lib.getExe hs.hyprDpmsAllOn}"
    ];

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

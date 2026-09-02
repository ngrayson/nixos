# f.lux-equivalent display warmth by sunrise/sunset. Applies to every desktop
# host importing home/default.nix (Tawa + Theseus). Hearth is headless and the
# Go3 wall kiosk has no reason to shift colour temperature, so neither gets it.
#
# Why gammastep: redshift is X11-native and needs an XWayland shim under
# Hyprland; wlsunset is wlroots-native but has neither automatic geolocation nor
# a manual override. gammastep is the maintained wlroots fork of redshift, ships
# a home-manager module, and is the closest match to what f.lux actually did.
#
# Location comes from geoclue2 rather than hardcoded coordinates, deliberately:
# this file is tracked in a public repo and home coordinates do not belong in
# it. The trade is that geoclue2 asks an external service roughly where this
# machine is (nixpkgs points services.geoclue2.geoProviderUrl at BeaconDB). To
# avoid that egress instead, drop `provider` and set `latitude`/`longitude`
# here — a one-line swap, not a redesign.
#
# geoclue2 is already enabled on both hosts (services.desktopManager.plasma6
# pulls it in) and needs no extra permission entry: checked 2026-09-02 with
# `gammastep -p -l geoclue2`, which returned a correct fix and solar period
# while /etc/geoclue/geoclue.conf listed only epiphany and firefox. So it
# answers unlisted clients. If a future geoclue release tightens that, the fix
# is one `services.geoclue2.appConfig.gammastep` entry with `isAllowed = true`
# -- the symptom would be this service starting cleanly and never getting a fix.
{...}: {
  services.gammastep = {
    enable = true;
    provider = "geoclue2";

    # 6500K is "unchanged" daylight; 3700K is a clear evening shift without
    # going orange. Comfortable starting points, not researched-optimal ones.
    temperature = {
      day = 6500;
      night = 3700;
    };

    # Off deliberately. `tray = true` swaps the plain daemon for
    # gammastep-indicator, a GTK/AppIndicator app, which would make the colour
    # shifting depend on that GUI component starting. Quickshell does host a
    # system tray so it would probably work, but it could not be verified
    # without an activation, and a failed indicator means no warmth at all
    # rather than merely no icon. Flip this on once someone has watched it come
    # up.
    tray = false;
  };
}

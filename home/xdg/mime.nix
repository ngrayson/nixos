# User-side MIME plumbing. The default associations themselves are a system baseline in
# `../../common/mime.nix` (`/etc/xdg/mimeapps.list`), which keeps `~/.config/mimeapps.list` writable
# so defaults picked in an application still persist.
{
  config,
  lib,
  pkgs,
  ...
}: {
  # GIO resolves MIME -> app for `~/.local/share/applications` through `mimeinfo.cache`, and nothing
  # regenerates it there (NixOS `xdg.mime` only builds the caches in system data dirs).
  home.activation.userDesktopDatabase = lib.hm.dag.entryAfter ["linkGeneration"] ''
    if [ -d "${config.xdg.dataHome}/applications" ]; then
      $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database -q "${config.xdg.dataHome}/applications"
    fi
  '';
}

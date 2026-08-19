# Baseline MIME defaults, installed as `/etc/xdg/mimeapps.list`.
#
# `/etc/xdg` sits in `XDG_CONFIG_DIRS`, which the spec searches *after* `$XDG_CONFIG_HOME/mimeapps.list`.
# So this file gives every host reproducible defaults while leaving `~/.config/mimeapps.list` an
# ordinary writable file: "Set as default" in Dolphin or Firefox persists there and overrides these.
#
# Do not manage the user file with Home Manager's `xdg.mimeApps` instead. That makes it a read-only
# store symlink, and every GUI write path then resolves the symlink and fails trying to write its
# temp file into /nix/store -- xdg-utils and GIO at least report an error, while KConfig (the path
# Dolphin's "always use this application" takes) fails completely silently.
{lib, ...}: let
  # Gwenview's declared MimeType list minus `inode/directory`, which Dolphin owns.
  imageMimes = [
    "image/avif"
    "image/bmp"
    "image/gif"
    "image/heif"
    "image/jpeg"
    "image/jxl"
    "image/openraster"
    "image/png"
    "image/svg+xml"
    "image/svg+xml-compressed"
    "image/tiff"
    "image/webp"
    "image/x-eps"
    "image/x-icns"
    "image/x-ico"
    "image/x-portable-bitmap"
    "image/x-portable-graymap"
    "image/x-portable-pixmap"
    "image/x-psd"
    "image/x-tga"
    "image/x-webp"
    "image/x-xbitmap"
    "image/x-xcf"
    "image/x-xpixmap"
  ];

  mediaMimes = [
    "audio/aac"
    "audio/flac"
    "audio/mp4"
    "audio/mpeg"
    "audio/ogg"
    "audio/opus"
    "audio/x-vorbis+ogg"
    "audio/x-wav"
    "video/3gpp"
    "video/mp4"
    "video/mpeg"
    "video/ogg"
    "video/quicktime"
    "video/webm"
    "video/x-flv"
    "video/x-matroska"
    "video/x-msvideo"
  ];

  # `application/x-extension-*` are synthetic types xdg-settings uses for bare file extensions;
  # Firefox does not declare them, so they need an explicit association to appear as candidates.
  browserExtensionMimes = [
    "application/x-extension-htm"
    "application/x-extension-html"
    "application/x-extension-shtml"
    "application/x-extension-xht"
    "application/x-extension-xhtml"
  ];

  browserMimes =
    browserExtensionMimes
    ++ [
      "application/xhtml+xml"
      "text/html"
      "x-scheme-handler/chrome"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];

  assign = app: mimes: lib.genAttrs mimes (_: app);

  defaultApplications =
    assign "org.kde.gwenview.desktop" imageMimes
    // assign "vlc.desktop" mediaMimes
    // assign "firefox.desktop" browserMimes
    // {
      "inode/directory" = "org.kde.dolphin.desktop";
      "application/pdf" = "firefox.desktop";
      "text/plain" = "org.kde.kate.desktop";
      "x-scheme-handler/bitwarden" = "bitwarden.desktop";
      "x-scheme-handler/cursor" = "cursor-url-handler.desktop";
    };

  # Deliberately omits `application/octet-stream`: it is the fallback type for every unrecognised
  # binary, so pointing it at an application sends arbitrary files there.
  addedAssociations = assign "firefox.desktop" browserExtensionMimes;

  # `mapAttrsToList` walks attributes in sorted order, so the rendered file is deterministic.
  renderEntries = attrs: lib.mapAttrsToList (mime: app: "${mime}=${app}") attrs;
in {
  environment.etc."xdg/mimeapps.list".text = lib.concatStringsSep "\n" (
    ["[Added Associations]"]
    ++ renderEntries addedAssociations
    ++ ["" "[Default Applications]"]
    ++ renderEntries defaultApplications
    ++ [""]
  );
}

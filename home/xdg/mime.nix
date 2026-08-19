# Declarative MIME defaults (`~/.config/mimeapps.list`).
#
# `xdg.mimeApps.enable` replaces that file with a read-only store symlink, so "Set as default" /
# "Always open with" inside an application no longer persists — edit the lists below instead.
# This is deliberate: the previous mutable file had accumulated `image/png=feh-2.desktop`, a
# hand-written stub with no `%f` in `Exec` and `NoDisplay=true`, which KIO rejects as a handler.
{
  config,
  lib,
  pkgs,
  ...
}: let
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
in {
  xdg.mimeApps = {
    enable = true;

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

    # Intentionally omits the old `application/octet-stream=pixel-composer.desktop`: that type is
    # the fallback for every unrecognised binary, so it sent arbitrary files to Pixel Composer.
    associations.added = assign "firefox.desktop" browserExtensionMimes;
  };

  # GIO looks up MIME -> app for `~/.local/share/applications` through `mimeinfo.cache`, and
  # nothing regenerates it there (NixOS `xdg.mime` only builds the caches in system data dirs).
  home.activation.userDesktopDatabase = lib.hm.dag.entryAfter ["linkGeneration"] ''
    if [ -d "${config.xdg.dataHome}/applications" ]; then
      $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database -q "${config.xdg.dataHome}/applications"
    fi
  '';
}

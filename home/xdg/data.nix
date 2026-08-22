{
  pkgs,
  lib,
  ...
}: let
  desktopDataFiles = import ../lib/desktop-data.nix {
    inherit lib;
    appDir = ../../desktop/applications;
  };
in {
  xdg.dataFile =
    desktopDataFiles
    // {
      # Own Cursor Exec here (pkgs.code-cursor) so Albert/menus never depend on a local AppImage.
      # desktop/applications/cursor*.desktop stay as readable templates; these entries win on rebuild.
      "applications/cursor.desktop" = {
        force = true;
        text = ''
          [Desktop Entry]
          Name=Cursor
          Comment=AI-first code editor
          TryExec=${lib.getExe pkgs.code-cursor}
          Exec=${lib.getExe pkgs.code-cursor} %F
          Icon=co.anysphere.cursor
          Terminal=false
          StartupNotify=true
          DBusActivatable=false
          Type=Application
          Categories=Development;IDE;TextEditor;
          StartupWMClass=cursor
          MimeType=text/plain;inode/directory;
        '';
      };
      "applications/cursor-url-handler.desktop" = {
        force = true;
        text = ''
          [Desktop Entry]
          Name=Cursor - URL Handler
          Comment=Open cursor:// links (e.g. MCP OAuth callbacks)
          TryExec=${lib.getExe pkgs.code-cursor}
          Exec=${lib.getExe pkgs.code-cursor} --open-url %U
          Icon=co.anysphere.cursor
          Type=Application
          NoDisplay=true
          StartupNotify=true
          Categories=Utility;TextEditor;Development;IDE;
          MimeType=x-scheme-handler/cursor;
          Keywords=cursor;
        '';
      };
      "applications/kitty.desktop" = {
        force = true;
        text = ''
          [Desktop Entry]
          Version=1.0
          Type=Application
          Name=kitty
          GenericName=Terminal emulator
          Comment=Fast, feature-rich, GPU based terminal
          TryExec=${pkgs.kitty}/bin/kitty
          StartupNotify=true
          Exec=${pkgs.kitty}/bin/kitty
          Icon=kitty
          Categories=System;TerminalEmulator;
          X-TerminalArgExec=--
          X-TerminalArgTitle=--title
          X-TerminalArgAppId=--class
          X-TerminalArgDir=--working-directory
          X-TerminalArgHold=--hold
        '';
      };
    };
}

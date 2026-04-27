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

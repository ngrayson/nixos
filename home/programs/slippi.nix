# Slippi Launcher (slippi-nix HM module is imported in `common/system.nix`).
#
# The upstream launcher auto-downloads raw Dolphin AppImages when its version check
# disagrees with the Nix-wrapped build. On NixOS those raw AppImages are launched via
# binfmt/appimage-run and fail with CURL_OPENSSL_4. Use slippi-launcher-desktop so
# Nix-wrapped Dolphin paths are re-symlinked before every launcher start.
{
  lib,
  pkgs,
  slippi-nix-src,
  ...
}: let
  slippi-launcher-base = pkgs.callPackage "${slippi-nix-src}/packages/slippi-launcher.nix" {};
  slippi-netplay = pkgs.callPackage "${slippi-nix-src}/packages/slippi-netplay.nix" {};
  slippi-netplay-beta = pkgs.callPackage "${slippi-nix-src}/packages/slippi-netplay-beta.nix" {};
  slippi-playback = pkgs.callPackage "${slippi-nix-src}/packages/slippi-playback.nix" {};
in {
  slippi-launcher = {
    enable = true;
    isoPath = lib.mkDefault "";
  };

  # Launcher or manual fixes can leave non-HM files here; allow activation to replace them.
  home.file.".config/Slippi Launcher/netplay/Slippi_Online-x86_64.AppImage".force = true;
  home.file.".config/Slippi Launcher/netplay-beta/Slippi_Netplay_Mainline-x86_64.AppImage".force = true;
  home.file.".config/Slippi Launcher/playback/Slippi_Playback-x86_64.AppImage".force = true;

  home.packages = [
    (lib.hiPrio (
      pkgs.callPackage "${slippi-nix-src}/packages/slippi-launcher-desktop.nix" {
        inherit (pkgs) formats;
        slippi-launcher = slippi-launcher-base;
        inherit slippi-netplay slippi-netplay-beta slippi-playback;
      }
    ))
  ];
}

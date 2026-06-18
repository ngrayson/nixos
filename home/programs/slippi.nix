# Slippi: HM module (declarative settings + Dolphin paths) is imported in `common/system.nix`.
# Launcher entry point follows upstream default: `slippi-launcher-desktop` (symlinks
# Nix-wrapped Dolphin on each start). See https://github.com/lytedev/slippi-nix
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

  slippi-launcher-desktop = pkgs.callPackage "${slippi-nix-src}/packages/slippi-launcher-desktop.nix" {
    inherit (pkgs) formats;
    slippi-launcher = slippi-launcher-base;
    inherit slippi-netplay slippi-netplay-beta slippi-playback;
  };
in {
  slippi-launcher = {
    enable = true;
    # Set your NTSC Melee ISO path here, or via the launcher UI (merged on next activation).
    isoPath = lib.mkDefault "";
  };

  home.packages = [(lib.hiPrio slippi-launcher-desktop)];
}

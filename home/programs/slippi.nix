# Slippi: HM module (declarative settings + Dolphin paths) is imported in `common/system.nix`.
# Launcher entry point: hardened wrapper around upstream `slippi-launcher-desktop`
# (re-symlinks Nix-wrapped Dolphin, clears stale Electron locks / stock overwrites).
# See https://github.com/lytedev/slippi-nix
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

  # Upstream desktop entry Exec= points at the raw FHS binary (skips symlink seeding).
  # Also: launcher auto-update can leave a real AppImage + Sys/ dir that breaks ln -sfn,
  # and Electron console logging throws unhandled EIO when stdout is a broken pipe.
  slippi-launcher-hardened = pkgs.writeShellApplication {
    name = "slippi-launcher";
    text = ''
      set -euo pipefail
      slippi_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/Slippi Launcher"

      # Drop stale singleton locks from crashed prior runs (dead PID → silent no-op launch).
      lock="$slippi_dir/SingletonLock"
      if [[ -L "$lock" ]]; then
        lock_target="$(readlink "$lock" || true)"
        lock_pid="''${lock_target##*-}"
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
          rm -f "$lock" "$slippi_dir/SingletonCookie" "$slippi_dir/SingletonSocket"
        fi
      fi

      # Stock auto-update replaces Nix symlinks with a real AppImage + Sys directory.
      # ln -sfn cannot replace a real directory (it nests Sys/Sys instead).
      for rel in \
        netplay/Slippi_Online-x86_64.AppImage \
        netplay/Sys \
        netplay-beta/Slippi_Netplay_Mainline-x86_64.AppImage \
        netplay-beta/Sys \
        playback/Slippi_Playback-x86_64.AppImage \
        playback/Sys
      do
        p="$slippi_dir/$rel"
        if [[ -e "$p" && ! -L "$p" ]]; then
          rm -rf "$p"
        fi
      done
      rm -f "$slippi_dir/netplay/Slippi_Online-x86_64.AppImage.zsync" || true

      # Avoid unhandled EIO from electron-log console transport when GUI stdio is closed.
      exec ${lib.getExe slippi-launcher-desktop} "$@" >/dev/null 2>&1
    '';
  };
in {
  slippi-launcher = {
    enable = true;
    # Set your NTSC Melee ISO path here, or via the launcher UI (merged on next activation).
    isoPath = lib.mkDefault "";
  };

  home.packages = [(lib.hiPrio slippi-launcher-hardened)];

  # Override the .desktop from the base launcher package so Albert/menus use the wrapper.
  xdg.desktopEntries.slippi-launcher = {
    name = "Slippi Launcher";
    comment = "Launch Slippi Online, browse and watch saved replays";
    exec = "${lib.getExe slippi-launcher-hardened} %U";
    icon = "slippi-launcher";
    terminal = false;
    categories = ["Game"];
    mimeType = ["x-scheme-handler/slippi" "application/x-slippi"];
    settings = {
      StartupWMClass = "Slippi Launcher";
    };
  };

  # Before HM link generation, remove stock files that would clobber home.file symlinks.
  home.activation.slippiRemoveStockDolphin = lib.hm.dag.entryBefore ["linkGeneration"] ''
    slippi_dir="$HOME/.config/Slippi Launcher"
    for rel in \
      netplay/Slippi_Online-x86_64.AppImage \
      netplay/Sys \
      netplay-beta/Slippi_Netplay_Mainline-x86_64.AppImage \
      netplay-beta/Sys \
      playback/Slippi_Playback-x86_64.AppImage \
      playback/Sys
    do
      p="$slippi_dir/$rel"
      if [ -e "$p" ] && [ ! -L "$p" ]; then
        rm -rf "$p"
      fi
    done
    rm -f "$slippi_dir/netplay/Slippi_Online-x86_64.AppImage.zsync" || true
  '';
}

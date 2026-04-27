# Hyprland helper derivations (paths relative to this file: ../../quickshell, etc.)
{
  config,
  lib,
  pkgs,
}: let
  quickshellBundled = pkgs.runCommand "quickshell-hm-config" {} ''
    mkdir -p $out/pam
    cp ${../../quickshell/shell.qml} $out/shell.qml
    cp ${../../quickshell/LockContext.qml} $out/LockContext.qml
    cp ${../../quickshell/LockSurface.qml} $out/LockSurface.qml
    cp ${../../quickshell/pam/password.conf} $out/pam/password.conf
  '';

  quickshellConfigDir = "${config.home.homeDirectory}/.config/quickshell";
in {
  inherit quickshellBundled quickshellConfigDir;

  hyprScreenshotRegion = pkgs.writeShellScriptBin "hypr-screenshot-region" ''
    set -euo pipefail
    ${lib.getExe pkgs.grim} -g "$(${lib.getExe pkgs.slurp})" - | ${pkgs.wl-clipboard}/bin/wl-copy --type image
  '';

  quickshellLock = pkgs.writeShellScriptBin "quickshell-lock" ''
    set -euo pipefail
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    QS="''${HOME}/.config/quickshell"
    exec env WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-}" XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR}" \
      ${lib.getExe pkgs.quickshell} ipc -p "$QS" -n call lock activate
  '';

  hyprDpmsAllOff = pkgs.writeShellScriptBin "hypr-dpms-all-off" ''
    set -euo pipefail
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    H="${pkgs.hyprland}/bin/hyprctl"
    J="${lib.getExe pkgs.jq}"
    "$H" -i 0 dispatch dpms off || true
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      "$H" -i 0 dispatch dpms off "$name" || true
    done < <("$H" -i 0 monitors -j | "$J" -r '.[].name')
  '';

  hyprDpmsAllOn = pkgs.writeShellScriptBin "hypr-dpms-all-on" ''
    set -euo pipefail
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    H="${pkgs.hyprland}/bin/hyprctl"
    "$H" -i 0 dispatch dpms on || true
    sleep 1
    "$H" -i 0 dispatch dpms on || true
  '';
}

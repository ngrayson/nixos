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
in rec {
  inherit quickshellBundled quickshellConfigDir;

  # Super+Shift+S / Print: region capture via hyprshot (clipboard only; spectacle needs KWin on Wayland).
  hyprScreenshotRegion = pkgs.writeShellScriptBin "hypr-screenshot-region" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.hyprshot} -m region --clipboard-only
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

  # Lock then blank outputs before systemd suspend (quickshell-lock uses exec and cannot be chained).
  hyprBeforeSleep = pkgs.writeShellScriptBin "hypr-before-sleep" ''
    set -euo pipefail
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    QS="''${HOME}/.config/quickshell"
    env WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-}" XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR}" \
      ${lib.getExe pkgs.quickshell} ipc -p "$QS" -n call lock activate
    sleep 1
    ${lib.getExe hyprDpmsAllOff}
  '';

  hyprDpmsAllOn = pkgs.writeShellScriptBin "hypr-dpms-all-on" ''
    set -euo pipefail
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    H="${pkgs.hyprland}/bin/hyprctl"
    "$H" -i 0 dispatch dpms on || true
    sleep 1
    "$H" -i 0 dispatch dpms on || true
  '';

  # Toggle PulseAudio UI: used by Quickshell bar (PATH) and matches Hyprland `pavucontrol` window rules.
  # Must background Pavu (no `exec`): Quickshell wraps this in `Process` and only one run can be active;
  # `exec pavucontrol` would keep that process open until the window closes, so a second bar click never ran.
  pavuToggle = pkgs.writeShellScriptBin "pavu-toggle" ''
    set -eu
    PAVU="${lib.getExe pkgs.pavucontrol}"
    if pgrep -x pavucontrol >/dev/null 2>&1; then
      pkill -x pavucontrol
    else
      "$PAVU" >/dev/null 2>&1 &
    fi
  '';

  # Close focused pavucontrol on Escape (Hyprland `bindn` runs this but still passes Escape to apps).
  pavuEscapeClose = pkgs.writeShellScriptBin "pavu-escape-close" ''
    set -eu
    H="${pkgs.hyprland}/bin/hyprctl"
    J="${lib.getExe pkgs.jq}"
    class="$("$H" activewindow -j 2>/dev/null | "$J" -r '.class // empty' || true)"
    case "$class" in
      *pavucontrol*)
        "$H" dispatch killactive
        ;;
    esac
  '';
}

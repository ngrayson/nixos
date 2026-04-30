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

  # True when Slippi Dolphin netplay is actively emulating (launcher-only should not match).
  slippiIsEmulating = pkgs.writeShellScriptBin "slippi-is-emulating" ''
    set -euo pipefail
    # Match active netplay emulation only:
    # - cmdline contains Slippi netplay AppImage
    # - cmdline includes ` -e <iso>` launch argument
    # Launcher-only processes do not include ` -e `.
    for cmdline in /proc/[0-9]*/cmdline; do
      [[ -r "$cmdline" ]] || continue
      cmd="$(${lib.getExe' pkgs.coreutils "tr"} '\000' ' ' <"$cmdline" 2>/dev/null || true)"
      case "$cmd" in
        *Slippi_Online-x86_64.AppImage*" -e "*) exit 0 ;;
      esac
    done
    exit 1
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

  # Suppress idle lock while Slippi emulation is active.
  quickshellLockGuarded = pkgs.writeShellScriptBin "quickshell-lock-guarded" ''
    set -euo pipefail
    if ${lib.getExe slippiIsEmulating}; then
      exit 0
    fi
    exec ${lib.getExe quickshellLock}
  '';

  # Suppress DPMS blanking while Slippi emulation is active.
  hyprDpmsAllOffGuarded = pkgs.writeShellScriptBin "hypr-dpms-all-off-guarded" ''
    set -euo pipefail
    if ${lib.getExe slippiIsEmulating}; then
      exit 0
    fi
    exec ${lib.getExe hyprDpmsAllOff}
  '';

  # Suspend after extended idle, but never while Slippi emulation is active.
  hyprSuspendGuarded = pkgs.writeShellScriptBin "hypr-suspend-guarded" ''
    set -euo pipefail
    if ${lib.getExe slippiIsEmulating}; then
      exit 0
    fi
    exec ${lib.getExe' pkgs.systemd "systemctl"} suspend
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
  # Detection uses Hyprland clients (class contains "pavucontrol"): `pgrep -x` often misses the real process name.
  pavuToggle = pkgs.writeShellScriptBin "pavu-toggle" ''
    set -eu
    PAVU="${lib.getExe pkgs.pavucontrol}"
    H="${pkgs.hyprland}/bin/hyprctl"
    J="${lib.getExe pkgs.jq}"
    clients="$("$H" -i 0 clients -j 2>/dev/null || true)"
    case "''$clients" in
      \[*) ;;
      *) clients="[]" ;;
    esac
    pid="$("$J" -r '[.[]? | select(((.class // "") | ascii_downcase | contains("pavucontrol"))) | .pid][0] // empty' <<<"''$clients")"
    if [ -n "$pid" ] && [ "$pid" != "null" ]; then
      kill -TERM "$pid" 2>/dev/null || true
    else
      "$PAVU" >/dev/null 2>&1 &
    fi
  '';

  # Close focused pavucontrol on Escape (Hyprland `bindn` runs this but still passes Escape to apps).
  pavuEscapeClose = pkgs.writeShellScriptBin "pavu-escape-close" ''
    set -eu
    H="${pkgs.hyprland}/bin/hyprctl"
    J="${lib.getExe pkgs.jq}"
    class="$("$H" -i 0 activewindow -j 2>/dev/null | "$J" -r '.class // empty' || true)"
    case "$class" in
      *pavucontrol*)
        "$H" -i 0 dispatch killactive
        ;;
    esac
  '';
}

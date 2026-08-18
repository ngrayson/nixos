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

  # True when Deluge UI is running; used to block idle suspend while seeding.
  delugeIsRunning = pkgs.writeShellScriptBin "deluge-is-running" ''
    set -euo pipefail
    for cmdline in /proc/[0-9]*/cmdline; do
      [[ -r "$cmdline" ]] || continue
      cmd="$(${lib.getExe' pkgs.coreutils "tr"} '\000' ' ' <"$cmdline" 2>/dev/null || true)"
      case "$cmd" in
        *deluge-gtk*|*org.deluge.Deluge*) exit 0 ;;
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

  # Suspend after extended idle, but never while Slippi emulation or Deluge is active.
  hyprSuspendGuarded = pkgs.writeShellScriptBin "hypr-suspend-guarded" ''
    set -euo pipefail
    if ${lib.getExe slippiIsEmulating}; then
      exit 0
    fi
    if ${lib.getExe delugeIsRunning}; then
      exit 0
    fi
    exec ${lib.getExe' pkgs.systemd "systemctl"} suspend
  '';

  # Lock, then re-enable outputs before systemd suspends (quickshell-lock uses exec and
  # cannot be chained). Suspending while the 600s idle listener has DPMS off leaves this
  # eDP panel dark on resume: `dispatch dpms on` then returns ok without lighting it.
  # Cost of waking outputs first is a brief flash before the machine goes down.
  hyprBeforeSleep = pkgs.writeShellScriptBin "hypr-before-sleep" ''
    set -euo pipefail
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    QS="''${HOME}/.config/quickshell"
    env WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-}" XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR}" \
      ${lib.getExe pkgs.quickshell} ipc -p "$QS" -n call lock activate
    ${lib.getExe' pkgs.coreutils "sleep"} 1
    ${lib.getExe hyprDpmsAllOn} || true
  '';

  # Verify instead of trusting `dispatch dpms on`: after s2idle it can report ok while
  # the panel stays black. Poll until Hyprland answers IPC, turn every output on by name,
  # then escalate to an off -> on cycle, which forces amdgpu to redo the modeset.
  hyprDpmsAllOn = pkgs.writeShellScriptBin "hypr-dpms-all-on" ''
    set -uo pipefail
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    H="${pkgs.hyprland}/bin/hyprctl"
    J="${lib.getExe pkgs.jq}"
    SLEEP="${lib.getExe' pkgs.coreutils "sleep"}"

    monitorsJson() {
      "$H" -i 0 monitors -j 2>/dev/null
    }

    dpmsOnAll() {
      "$H" -i 0 dispatch dpms on || true
      local name
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        "$H" -i 0 dispatch dpms on "$name" || true
      done < <(monitorsJson | "$J" -r '.[].name' 2>/dev/null)
    }

    allAwake() {
      local json dark
      json="$(monitorsJson)" || return 1
      case "$json" in
        \[*) ;;
        *) return 1 ;;
      esac
      dark="$("$J" -r '[.[] | select((.dpmsStatus // false) != true or (.disabled // false) == true)] | length' <<<"$json" 2>/dev/null)" || return 1
      [ "''${dark:-1}" = "0" ]
    }

    tries=0
    while [ "$tries" -lt 20 ]; do
      monitorsJson | "$J" -e 'length > 0' >/dev/null 2>&1 && break
      "$SLEEP" 0.25
      tries=$((tries + 1))
    done

    attempt=0
    while [ "$attempt" -lt 3 ]; do
      dpmsOnAll
      "$SLEEP" 1
      allAwake && exit 0
      "$H" -i 0 dispatch dpms off || true
      "$SLEEP" 1
      attempt=$((attempt + 1))
    done

    dpmsOnAll
    exit 0
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

  # Focus the window belonging to a tray item after SNI Activate. Tray items expose no PID
  # to the shell, so resolve id -> StatusNotifierWatcher entry -> D-Bus owner PID -> Hyprland
  # client. Name matching is not viable: Electron apps register as `chrome_status_icon_N`.
  hyprTrayFocus = pkgs.writeShellScriptBin "qs-tray-focus" ''
    set -eu
    id="''${1:-}"
    [ -n "$id" ] || exit 0

    BUSCTL="${lib.getExe' pkgs.systemd "busctl"}"
    H="${pkgs.hyprland}/bin/hyprctl"
    J="${lib.getExe pkgs.jq}"
    SLEEP="${lib.getExe' pkgs.coreutils "sleep"}"

    # True if $1 equals $2 or an ancestor of $1 (up to 6 hops) equals $2.
    # Steam's tray is the parent process; game/client windows are children.
    reaches_owner() {
      local pid="$1"
      local target="$2"
      local hops=0
      local ppid line
      while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ] && [ "$hops" -lt 6 ]; do
        if [ "$pid" = "$target" ]; then
          return 0
        fi
        ppid=""
        while IFS= read -r line || [ -n "$line" ]; do
          case "$line" in
            PPid:*)
              # shellcheck disable=SC2086
              set -- $line
              ppid="$2"
              ;;
          esac
        done <"/proc/$pid/status" 2>/dev/null || return 1
        [ -n "$ppid" ] || return 1
        pid="$ppid"
        hops=$((hops + 1))
      done
      return 1
    }

    items="$("$BUSCTL" --user --json=short get-property \
      org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
      org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems 2>/dev/null \
      | "$J" -r '.data[]? // empty' || true)"

    bus_name=""
    while IFS= read -r entry || [ -n "$entry" ]; do
      [ -n "$entry" ] || continue
      case "$entry" in
        */*)
          name="''${entry%%/*}"
          path="/''${entry#*/}"
          ;;
        *)
          name="$entry"
          path="/StatusNotifierItem"
          ;;
      esac
      item_id="$("$BUSCTL" --user --json=short get-property \
        "$name" "$path" org.kde.StatusNotifierItem Id 2>/dev/null \
        | "$J" -r '.data // empty' || true)"
      if [ "$item_id" = "$id" ]; then
        bus_name="$name"
        break
      fi
    done <<<"$items"

    [ -n "$bus_name" ] || exit 0

    owner_pid=""
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        PID=*) owner_pid="''${line#PID=}" ;;
      esac
    done < <("$BUSCTL" --user status "$bus_name" 2>/dev/null || true)
    [ -n "$owner_pid" ] || exit 0

    addr=""
    tries=0
    while [ "$tries" -lt 20 ]; do
      clients="$("$H" -i 0 clients -j 2>/dev/null || true)"
      case "$clients" in
        \[*) ;;
        *) clients="[]" ;;
      esac

      while IFS=$'\t' read -r _fh address pid || [ -n "$address" ]; do
        [ -n "''${address:-}" ] || continue
        [ -n "''${pid:-}" ] || continue
        if [ "$pid" = "$owner_pid" ] || reaches_owner "$pid" "$owner_pid"; then
          addr="$address"
          break
        fi
      done < <("$J" -r '
        [.[]?
          | select(.mapped == true and ((.hidden // false) == false) and (.address != null) and (.pid != null))
        ]
        | sort_by(.focusHistoryID // 9999)
        | .[]
        | "\(.focusHistoryID // 9999)\t\(.address)\t\(.pid)"
      ' <<<"$clients")

      [ -n "$addr" ] && break
      "$SLEEP" 0.1
      tries=$((tries + 1))
    done

    [ -n "$addr" ] || exit 0
    "$H" -i 0 dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
  '';

  # Bar status for unapplied NixOS config vs /run/current-system, and stale flake inputs.
  # Prints one JSON line: {"rebuild":bool,"updates":n}. Caches the expensive eval and the
  # network lock-file probe; `qs-nixos-status --force` bypasses both.
  hyprNixosStatus = pkgs.writeShellScriptBin "qs-nixos-status" ''
    set -eu
    FORCE=0
    [ "''${1:-}" = "--force" ] && FORCE=1

    NIX="${lib.getExe pkgs.nix}"
    GIT="${lib.getExe pkgs.git}"
    J="${lib.getExe pkgs.jq}"
    DATE="${lib.getExe' pkgs.coreutils "date"}"
    MKTEMP="${lib.getExe' pkgs.coreutils "mktemp"}"
    MKDIR="${lib.getExe' pkgs.coreutils "mkdir"}"
    CP="${lib.getExe' pkgs.coreutils "cp"}"
    RM="${lib.getExe' pkgs.coreutils "rm"}"
    SHA="${lib.getExe' pkgs.coreutils "sha256sum"}"
    READLINK="${lib.getExe' pkgs.coreutils "readlink"}"
    UNAME="${lib.getExe' pkgs.coreutils "uname"}"
    CAT="${lib.getExe' pkgs.coreutils "cat"}"

    NIXOS_DIR="''${NIXOS_DIR:-$HOME/.config/nixos}"
    HOST="''${NIXOS_HOST:-$("$UNAME" -n)}"
    CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/qs-nixos-status"
    "$MKDIR" -p "$CACHE"
    INPUT_TTL=21600

    lock_hash() {
      "$SHA" <"$NIXOS_DIR/flake.lock" | {
        read -r h _
        printf '%s' "$h"
      }
    }

    fingerprint() {
      {
        printf 'host=%s\n' "$HOST"
        printf 'current=%s\n' "$("$READLINK" -f /run/current-system 2>/dev/null || true)"
        printf 'head=%s\n' "$("$GIT" -C "$NIXOS_DIR" rev-parse HEAD 2>/dev/null || printf none)"
        "$GIT" -C "$NIXOS_DIR" diff --binary HEAD 2>/dev/null || true
      } | "$SHA" | {
        read -r h _
        printf '%s' "$h"
      }
    }

    print_status() {
      "$J" -nc --argjson rebuild "$1" --argjson updates "$2" \
        '{rebuild:$rebuild,updates:$updates}'
    }

    rebuild=false
    updates=0
    fp="$(fingerprint)"
    lh="$(lock_hash)"

    if [ "$FORCE" != 1 ] && [ -f "$CACHE/fingerprint" ] && [ -f "$CACHE/local.json" ]; then
      if [ "$fp" = "$("$CAT" "$CACHE/fingerprint")" ]; then
        rebuild="$("$J" -r '.rebuild' "$CACHE/local.json")"
      fi
    fi

    if [ "$FORCE" = 1 ] || [ ! -f "$CACHE/local.json" ] || [ "$fp" != "$("$CAT" "$CACHE/fingerprint" 2>/dev/null || true)" ]; then
      current="$("$READLINK" -f /run/current-system 2>/dev/null || true)"
      expected=""
      if expected="$("$NIX" eval --raw \
        "$NIXOS_DIR#nixosConfigurations.''${HOST}.config.system.build.toplevel" \
        2>/dev/null)"; then
        if [ -n "$current" ] && [ "$current" != "$expected" ]; then
          rebuild=true
        else
          rebuild=false
        fi
        "$J" -nc --argjson rebuild "$rebuild" '{rebuild:$rebuild}' >"$CACHE/local.json"
        printf '%s' "$fp" >"$CACHE/fingerprint"
      elif [ -f "$CACHE/local.json" ]; then
        rebuild="$("$J" -r '.rebuild' "$CACHE/local.json")"
      fi
    fi

    reuse_inputs=0
    if [ "$FORCE" != 1 ] && [ -f "$CACHE/inputs.json" ]; then
      cached_lock="$("$J" -r '.lock' "$CACHE/inputs.json" 2>/dev/null || true)"
      cached_at="$("$J" -r '.checked_at' "$CACHE/inputs.json" 2>/dev/null || printf 0)"
      now="$("$DATE" +%s)"
      age=$((now - cached_at))
      if [ "$cached_lock" = "$lh" ] && [ "$age" -lt "$INPUT_TTL" ]; then
        updates="$("$J" -r '.updates' "$CACHE/inputs.json")"
        reuse_inputs=1
      fi
    fi

    if [ "$reuse_inputs" = 0 ]; then
      tmp="$("$MKTEMP" -d)"
      trap '"$RM" -rf "$tmp"' EXIT
      "$CP" "$NIXOS_DIR/flake.nix" "$NIXOS_DIR/flake.lock" "$tmp/"
      if (cd "$tmp" && "$NIX" flake update >/dev/null 2>&1); then
        updates="$("$J" -n --slurpfile old "$NIXOS_DIR/flake.lock" --slurpfile new "$tmp/flake.lock" '
          def ident($lock; $name):
            ($lock.nodes[$lock.nodes.root.inputs[$name]].locked // {})
            | (.rev // .narHash // "");
          ($old[0].nodes.root.inputs | keys) as $ks
          | [$ks[] | select(ident($old[0]; .) != ident($new[0]; .))] | length
        ')"
        "$J" -nc --argjson updates "$updates" --arg lock "$lh" --argjson checked_at "$("$DATE" +%s)" \
          '{updates:$updates,lock:$lock,checked_at:$checked_at}' >"$CACHE/inputs.json"
      elif [ -f "$CACHE/inputs.json" ]; then
        updates="$("$J" -r '.updates' "$CACHE/inputs.json")"
      else
        updates=0
      fi
      "$RM" -rf "$tmp"
      trap - EXIT
    fi

    print_status "$rebuild" "$updates"
  '';

  # Interactive Kitty that stays open after os-rebuild / flake update finish.
  hyprNixosTerm = pkgs.writeShellScriptBin "qs-nixos-term" ''
    set -eu
    KITTY="${lib.getExe pkgs.kitty}"
    BASH="${lib.getExe pkgs.bash}"
    NIX="${lib.getExe pkgs.nix}"
    REBUILD="${../../documentation/nixos-framework-setup/os-rebuild.sh}"
    FLAKE="${config.home.homeDirectory}/.config/nixos"
    case "''${1:-}" in
      rebuild)
        exec "$KITTY" --hold --title os-rebuild "$BASH" "$REBUILD" switch
        ;;
      update)
        exec "$KITTY" --hold --title flake-update "$BASH" -c "cd \"$FLAKE\" && exec \"$NIX\" flake update"
        ;;
      *)
        exit 2
        ;;
    esac
  '';
}

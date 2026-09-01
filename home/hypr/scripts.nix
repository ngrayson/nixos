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
    cp ${../../quickshell/PowerMenu.qml} $out/PowerMenu.qml
    cp ${../../quickshell/Theme.qml} $out/Theme.qml
    cp ${../../quickshell/qmldir} $out/qmldir
    cp ${../../quickshell/pam/password.conf} $out/pam/password.conf
  '';

  quickshellConfigDir = "${config.home.homeDirectory}/.config/quickshell";
  quickshellLiveDir = "${config.home.homeDirectory}/.config/nixos/quickshell";
  qsBin = lib.getExe pkgs.quickshell;
  # Session start, reload, and IPC all use the flake tree. HM ~/.config/quickshell
  # is only a fallback if the checkout is missing.
  qsLiveDirSnippet = ''
    qs_live_dir() {
      local nixos="''${HOME}/.config/nixos/quickshell"
      local hm="''${HOME}/.config/quickshell"
      if [ -f "$nixos/shell.qml" ]; then
        printf '%s\n' "$nixos"
      else
        printf '%s\n' "$hm"
      fi
    }
  '';
in rec {
  inherit quickshellBundled quickshellConfigDir quickshellLiveDir;

  # Super+Shift+S / Print: region capture via hyprshot (clipboard only; spectacle needs KWin on Wayland).
  hyprScreenshotRegion = pkgs.writeShellScriptBin "hypr-screenshot-region" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.hyprshot} -m region --clipboard-only
  '';

  # IPC to whichever bar is actually running (HM path or live nixos tree).
  hyprQuickshellIpc = pkgs.writeShellScriptBin "qs-quickshell-ipc" ''
    set -euo pipefail
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    ${qsLiveDirSnippet}
    QS="$(qs_live_dir)"
    exec env WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-}" XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR}" \
      ${qsBin} ipc -p "$QS" -n "$@"
  '';

  quickshellLock = pkgs.writeShellScriptBin "quickshell-lock" ''
    set -euo pipefail
    exec ${lib.getExe hyprQuickshellIpc} call lock activate
  '';

  # Overlay preview of the lock UI. Esc dismisses; does not take ext-session-lock.
  quickshellLockPreview = pkgs.writeShellScriptBin "quickshell-lock-preview" ''
    set -euo pipefail
    exec ${lib.getExe hyprQuickshellIpc} call lock preview
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

  # Blank every output except the geometric center panel (same midpoint heuristic as
  # Quickshell `centerOutputScreen`). Used while the session is locked so side
  # monitors go dark the way the SDDM greeter does on Tawa.
  hyprDpmsSideOff = pkgs.writeShellScriptBin "hypr-dpms-side-off" ''
    set -euo pipefail
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    H="${pkgs.hyprland}/bin/hyprctl"
    J="${lib.getExe pkgs.jq}"
    json="$("$H" -i 0 monitors -j 2>/dev/null || true)"
    case "$json" in
      \[*) ;;
      *) exit 0 ;;
    esac
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      "$H" -i 0 dispatch dpms off "$name" || true
    done < <("$J" -r '
      if length <= 1 then empty
      else
        (map(.x) | min) as $minX
        | (map(.x + .width) | max) as $maxX
        | (($minX + $maxX) / 2) as $mid
        | (sort_by((.x + (.width / 2) - $mid) | fabs) | .[0].name) as $center
        | .[] | select(.name != $center) | .name
      end
    ' <<<"$json")
  '';

  hyprDpmsSideOn = pkgs.writeShellScriptBin "hypr-dpms-side-on" ''
    set -euo pipefail
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    H="${pkgs.hyprland}/bin/hyprctl"
    J="${lib.getExe pkgs.jq}"
    json="$("$H" -i 0 monitors -j 2>/dev/null || true)"
    case "$json" in
      \[*) ;;
      *) exit 0 ;;
    esac
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      "$H" -i 0 dispatch dpms on "$name" || true
    done < <("$J" -r '
      if length <= 1 then empty
      else
        (map(.x) | min) as $minX
        | (map(.x + .width) | max) as $maxX
        | (($minX + $maxX) / 2) as $mid
        | (sort_by((.x + (.width / 2) - $mid) | fabs) | .[0].name) as $center
        | .[] | select(.name != $center) | .name
      end
    ' <<<"$json")
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

  # Theseus lid/idle path: same guards, then suspend-then-hibernate so a dead
  # battery can resume from the swap partition instead of a cold boot.
  hyprSuspendThenHibernateGuarded = pkgs.writeShellScriptBin "hypr-suspend-then-hibernate-guarded" ''
    set -euo pipefail
    if ${lib.getExe slippiIsEmulating}; then
      exit 0
    fi
    if ${lib.getExe delugeIsRunning}; then
      exit 0
    fi
    exec ${lib.getExe' pkgs.systemd "systemctl"} suspend-then-hibernate
  '';

  # Lock, then re-enable outputs before systemd suspends (quickshell-lock uses exec and
  # cannot be chained). Suspending while the 600s idle listener has DPMS off leaves this
  # eDP panel dark on resume: `dispatch dpms on` then returns ok without lighting it.
  # Cost of waking outputs first is a brief flash before the machine goes down.
  hyprBeforeSleep = pkgs.writeShellScriptBin "hypr-before-sleep" ''
    set -euo pipefail
    : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
    ${lib.getExe hyprQuickshellIpc} call lock activate
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

  # Bar status for unapplied NixOS config vs /run/current-system, stale flake
  # inputs, and commits on the git remote not yet pulled. Prints one JSON line:
  # {"rebuild":bool,"updates":n,"behind":n}. Caches the expensive eval, the
  # network lock-file probe, and git fetch; `qs-nixos-status --force` bypasses them.
  # `--online` (from the bar when a connection exists) allows a periodic fetch.
  hyprNixosStatus = pkgs.writeShellScriptBin "qs-nixos-status" ''
    set -eu
    FORCE=0
    ONLINE=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --force) FORCE=1 ;;
        --online) ONLINE=1 ;;
        --invalidate|--invalidate-local)
          CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/qs-nixos-status"
          "${lib.getExe' pkgs.coreutils "mkdir"}" -p "$CACHE"
          "${lib.getExe' pkgs.coreutils "rm"}" -f "$CACHE/fingerprint" "$CACHE/local.json"
          "${lib.getExe' pkgs.coreutils "date"}" +%s >"$CACHE/bump"
          exit 0
          ;;
        --invalidate-inputs)
          CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/qs-nixos-status"
          "${lib.getExe' pkgs.coreutils "mkdir"}" -p "$CACHE"
          "${lib.getExe' pkgs.coreutils "rm"}" -f "$CACHE/inputs.json"
          "${lib.getExe' pkgs.coreutils "date"}" +%s >"$CACHE/bump"
          exit 0
          ;;
        *)
          break
          ;;
      esac
      shift
    done

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
    TIMEOUT="${lib.getExe' pkgs.coreutils "timeout"}"

    NIXOS_DIR="''${NIXOS_DIR:-$HOME/.config/nixos}"
    HOST="''${NIXOS_HOST:-$("$UNAME" -n)}"
    CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/qs-nixos-status"
    "$MKDIR" -p "$CACHE"
    INPUT_TTL=21600
    REMOTE_TTL=600

    # Docs/other-host edits dirty a git flake without changing this host's runtime.
    path_is_config() {
      local path="$1"
      case "$path" in
        documentation/* | scripts/* | .claude/* | *.md) return 1 ;;
        "hosts/$HOST/"*) return 0 ;;
        hosts/*) return 1 ;;
        *) return 0 ;;
      esac
    }

    relevant_dirty() {
      local line path
      "$GIT" -C "$NIXOS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
      while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        path="''${line:3}"
        case "$path" in
          *" -> "*) path="''${path##* -> }" ;;
        esac
        path_is_config "$path" && return 0
      done < <("$GIT" -C "$NIXOS_DIR" status --porcelain=v1 --untracked-files=all 2>/dev/null)
      return 1
    }

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
      "$J" -nc --argjson rebuild "$1" --argjson updates "$2" --argjson behind "$3" \
        '{rebuild:$rebuild,updates:$updates,behind:$behind}'
    }

    rebuild=false
    updates=0
    fp="v3-$(fingerprint)"
    lh="$(lock_hash)"
    current="$("$READLINK" -f /run/current-system 2>/dev/null || true)"
    head="$("$GIT" -C "$NIXOS_DIR" rev-parse HEAD 2>/dev/null || printf none)"

    if relevant_dirty; then
      rebuild=true
    elif [ -f "$CACHE/applied.json" ]; then
      applied_gen="$("$J" -r '.generation // empty' "$CACHE/applied.json" 2>/dev/null || true)"
      applied_head="$("$J" -r '.head // empty' "$CACHE/applied.json" 2>/dev/null || true)"
      if [ "$head" != "$applied_head" ] || { [ -n "$current" ] && [ "$current" != "$applied_gen" ]; }; then
        rebuild=true
      else
        rebuild=false
      fi
    else
      # First run: treat a clean tree as already applied so a dirty-build-then-commit
      # does not leave the wrench on (Nix hashes dirty vs committed sources differently).
      "$J" -nc --arg generation "$current" --arg head "$head" --arg host "$HOST" \
        '{generation:$generation,head:$head,host:$host}' >"$CACHE/applied.json"
      rebuild=false
    fi
    "$J" -nc --argjson rebuild "$rebuild" '{rebuild:$rebuild}' >"$CACHE/local.json"
    printf '%s' "$fp" >"$CACHE/fingerprint"

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

    do_fetch=0
    if [ "$ONLINE" = 1 ]; then
      if [ "$FORCE" = 1 ] || [ ! -f "$CACHE/remote.json" ]; then
        do_fetch=1
      else
        remote_at="$("$J" -r '.checked_at // 0' "$CACHE/remote.json" 2>/dev/null || printf 0)"
        now="$("$DATE" +%s)"
        age=$((now - remote_at))
        if [ "$age" -ge "$REMOTE_TTL" ]; then
          do_fetch=1
        fi
      fi
    fi
    if [ "$do_fetch" = 1 ]; then
      GIT_TERMINAL_PROMPT=0 "$TIMEOUT" 15 "$GIT" -C "$NIXOS_DIR" fetch --quiet origin >/dev/null 2>&1 || true
      "$J" -nc --argjson checked_at "$("$DATE" +%s)" '{checked_at:$checked_at}' >"$CACHE/remote.json"
    fi

    behind=0
    upstream="$("$GIT" -C "$NIXOS_DIR" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
    if [ -z "$upstream" ]; then
      branch="$("$GIT" -C "$NIXOS_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
      if [ -n "$branch" ] && "$GIT" -C "$NIXOS_DIR" rev-parse -q --verify "origin/$branch" >/dev/null 2>&1; then
        upstream="origin/$branch"
      elif "$GIT" -C "$NIXOS_DIR" rev-parse -q --verify origin/main >/dev/null 2>&1; then
        upstream=origin/main
      fi
    fi
    if [ -n "$upstream" ]; then
      behind="$("$GIT" -C "$NIXOS_DIR" rev-list --count "HEAD..$upstream" 2>/dev/null || printf 0)"
    fi
    behind=$((behind + 0))

    print_status "$rebuild" "$updates" "$behind"
  '';

  # Removable-USB inventory for the bar, as a JSON array (one object per whole
  # physical disk). Python rather than jq string-building: the payload nests
  # per-partition busy state, and lsblk already speaks JSON.
  hyprUsbStatus = pkgs.writeShellScriptBin "qs-usb-status" ''
    set -eu
    exec "${lib.getExe pkgs.python3}" - <<'PY'
    import json, subprocess

    LSBLK = "${lib.getExe' pkgs.util-linux "lsblk"}"
    FUSER = "${lib.getExe' pkgs.psmisc "fuser"}"
    PS = "${lib.getExe' pkgs.procps "ps"}"

    # Drivers that ARE the mount show up as holders of their own mountpoint.
    # Same exclusion hosts/Hearth/disk.nix makes before declaring COLD busy.
    MOUNT_DRIVERS = {"ntfs-3g", "mount.ntfs", "mount.ntfs-3g", "exfat-fuse", "mount.exfat"}


    def truthy(v):
        # lsblk emits real booleans on new util-linux and "0"/"1" on older ones.
        return v is True or v == "1" or v == 1


    def mountpoints(node):
        mps = node.get("mountpoints")
        if isinstance(mps, list):
            return [m for m in mps if m]
        one = node.get("mountpoint")
        return [one] if one else []


    def busy(mountpoint):
        """True if something other than the mount driver holds the mountpoint."""
        try:
            out = subprocess.run(
                [FUSER, "-m", mountpoint],
                capture_output=True, text=True, timeout=10,
            ).stdout
        except Exception:
            return False
        for pid in out.split():
            if not pid.isdigit():
                continue
            try:
                comm = subprocess.run(
                    [PS, "-o", "comm=", "-p", pid],
                    capture_output=True, text=True, timeout=5,
                ).stdout.strip()
            except Exception:
                comm = ""
            if comm and comm not in MOUNT_DRIVERS:
                return True
        return False


    try:
        raw = subprocess.run(
            [LSBLK, "-J", "-o", "NAME,PATH,LABEL,SIZE,MOUNTPOINT,MOUNTPOINTS,RM,HOTPLUG,TRAN,TYPE,FSTYPE"],
            capture_output=True, text=True, timeout=15, check=True,
        ).stdout
        tree = json.loads(raw).get("blockdevices") or []
    except Exception:
        print("[]")
        raise SystemExit(0)

    out = []
    for disk in tree:
        if disk.get("type") != "disk":
            continue
        # The safety boundary: only removable/hotplug USB disks are ever
        # reported, so an internal disk can never grow an eject pill.
        if disk.get("tran") != "usb":
            continue
        if not (truthy(disk.get("rm")) or truthy(disk.get("hotplug"))):
            continue

        parts = []
        for child in (disk.get("children") or []) or [disk]:
            fstype = child.get("fstype")
            mps = mountpoints(child)
            # Skip extended-partition containers and other unformatted slices.
            if not fstype and not mps:
                continue
            for mp in mps or [None]:
                parts.append({
                    "device": child.get("path") or ("/dev/" + (child.get("name") or "")),
                    "label": child.get("label") or "",
                    "mountpoint": mp,
                    "fstype": fstype,
                    "busy": busy(mp) if mp else False,
                })

        # Nothing mountable on this disk: no pill (a card reader with no card
        # inserted still enumerates as a USB disk).
        if not parts:
            continue

        # Most USB sticks carry no disk-level label, so fall back to the first
        # partition that has one — "boot" reads as a name, "vfat" does not.
        part_label = next((p["label"] for p in parts if p["label"]), "")

        out.append({
            "disk": disk.get("path") or ("/dev/" + (disk.get("name") or "")),
            "label": disk.get("label") or part_label or "USB",
            "size": disk.get("size") or "",
            "partitions": parts,
            "anyMounted": any(p["mountpoint"] for p in parts),
            "anyBusy": any(p["busy"] for p in parts),
        })

    print(json.dumps(out))
    PY
  '';

  # Safe eject for one whole USB disk: unmount every mounted partition, then
  # power the disk off. Fail-closed — a disk that would not fully unmount is
  # never powered off (same stance as hosts/Hearth/disk.nix's park abort).
  # Open one USB disk in Dolphin, mounting it first if nothing on it is
  # mounted yet. A pill is shown for plugged-in-but-unmounted disks too, so
  # left-click has to handle that case or it looks broken.
  hyprUsbOpen = pkgs.writeShellScriptBin "qs-usb-open" ''
    set -eu
    disk="''${1:-}"
    [ -n "$disk" ] || {
      printf 'usage: qs-usb-open /dev/sdX\n' >&2
      exit 2
    }

    LSBLK="${lib.getExe' pkgs.util-linux "lsblk"}"
    UDISKS="${lib.getExe' pkgs.udisks "udisksctl"}"
    DOLPHIN="${lib.getExe pkgs.kdePackages.dolphin}"

    # No removable/USB guard here, unlike qs-usb-eject: opening a folder is
    # not destructive. The block-device check just makes a typo fail loudly.
    [ -b "$disk" ] || {
      printf 'qs-usb-open: %s is not a block device\n' "$disk" >&2
      exit 1
    }

    first_mountpoint() {
      "$LSBLK" -nrpo MOUNTPOINT "$disk" | while read -r mnt; do
        [ -n "''${mnt:-}" ] || continue
        printf '%s\n' "$mnt"
        break
      done
    }

    mnt="$(first_mountpoint)"

    if [ -z "''${mnt:-}" ]; then
      # Nothing mounted — mount the first partition that has a filesystem.
      part="$("$LSBLK" -nrpo NAME,FSTYPE "$disk" | while read -r dev fstype; do
        [ -n "''${fstype:-}" ] || continue
        printf '%s\n' "$dev"
        break
      done)"
      if [ -z "''${part:-}" ]; then
        printf 'qs-usb-open: %s has no mountable filesystem\n' "$disk" >&2
        exit 1
      fi
      "$UDISKS" mount -b "$part" >/dev/null || {
        printf 'qs-usb-open: could not mount %s\n' "$part" >&2
        exit 1
      }
      # Re-query rather than parsing udisksctl's "Mounted X at Y" line — the
      # message format is not a stable interface.
      mnt="$(first_mountpoint)"
    fi

    if [ -z "''${mnt:-}" ]; then
      printf 'qs-usb-open: %s is still not mounted; not opening a file manager\n' "$disk" >&2
      exit 1
    fi

    exec "$DOLPHIN" "$mnt"
  '';

  hyprUsbEject = pkgs.writeShellScriptBin "qs-usb-eject" ''
    set -eu
    disk="''${1:-}"
    [ -n "$disk" ] || {
      printf 'usage: qs-usb-eject /dev/sdX\n' >&2
      exit 2
    }

    LSBLK="${lib.getExe' pkgs.util-linux "lsblk"}"
    UDISKS="${lib.getExe' pkgs.udisks "udisksctl"}"

    [ -b "$disk" ] || {
      printf 'qs-usb-eject: %s is not a block device\n' "$disk" >&2
      exit 1
    }

    # Re-check removability here rather than trusting the caller. qs-usb-status
    # is the boundary for what gets a pill, but this script can also be run by
    # hand, and powering off an internal disk must not be one keystroke away.
    tran="$("$LSBLK" -ndo TRAN "$disk" 2>/dev/null || true)"
    rm_flag="$("$LSBLK" -ndo RM "$disk" 2>/dev/null || true)"
    hot_flag="$("$LSBLK" -ndo HOTPLUG "$disk" 2>/dev/null || true)"
    if [ "$tran" != "usb" ] || { [ "$rm_flag" != "1" ] && [ "$hot_flag" != "1" ]; }; then
      printf 'qs-usb-eject: refusing %s (tran=%s rm=%s hotplug=%s) — not a removable USB disk\n' \
        "$disk" "$tran" "$rm_flag" "$hot_flag" >&2
      exit 1
    fi

    # Unmount every mounted partition first. A partition that will not unmount
    # aborts the whole eject, so we never power off a disk with live writeback.
    "$LSBLK" -nrpo NAME,MOUNTPOINT "$disk" | while read -r dev mnt; do
      [ -n "''${mnt:-}" ] || continue
      "$UDISKS" unmount -b "$dev" >/dev/null || {
        printf 'qs-usb-eject: could not unmount %s (%s) — leaving %s powered on\n' \
          "$dev" "$mnt" "$disk" >&2
        exit 1
      }
    done

    # The subshell above cannot fail the script through the pipe, so re-check
    # that nothing is still mounted before cutting power.
    still="$("$LSBLK" -nrpo MOUNTPOINT "$disk" | tr -d '[:space:]' || true)"
    if [ -n "$still" ]; then
      printf 'qs-usb-eject: %s still has a mounted partition — not powering off\n' "$disk" >&2
      exit 1
    fi

    "$UDISKS" power-off -b "$disk" >/dev/null || {
      printf 'qs-usb-eject: %s unmounted but power-off failed. Do not unplug yet.\n' "$disk" >&2
      exit 1
    }
  '';

  # Interactive Kitty that stays open after os-rebuild / flake update finish.
  hyprNixosTerm = pkgs.writeShellScriptBin "qs-nixos-term" ''
    set -eu
    KITTY="${lib.getExe pkgs.kitty}"
    BASH="${lib.getExe pkgs.bash}"
    NIX="${lib.getExe pkgs.nix}"
    GIT="${lib.getExe pkgs.git}"
    STATUS="${lib.getExe hyprNixosStatus}"
    REBUILD="${../../documentation/nixos-framework-setup/os-rebuild.sh}"
    FLAKE="${config.home.homeDirectory}/.config/nixos"
    case "''${1:-}" in
      rebuild)
        exec "$KITTY" --hold --title os-rebuild "$BASH" "$REBUILD" switch
        ;;
      update)
        exec "$KITTY" --hold --title flake-update "$BASH" -c \
          "cd \"$FLAKE\" && \"$NIX\" flake update; rc=\$?; \"$STATUS\" --invalidate-inputs >/dev/null 2>&1 || true; exit \$rc"
        ;;
      pull)
        exec "$KITTY" --title nixos-pull "$BASH" -lc \
          "cd \"$FLAKE\" && \"$GIT\" pull; \"$STATUS\" --invalidate-local >/dev/null 2>&1 || true; exec \"$BASH\" -l"
        ;;
      *)
        exit 2
        ;;
    esac
  '';

  # Restart the bar from the same flake tree Hyprland exec-once uses.
  # Detach first: the bar often execs this helper, and killing it would abort a
  # same-session pkill before every leftover instance is signaled.
  #
  # Do not use `pkill -x quickshell`: the Nix wrapper's /proc/pid/comm is
  # `.quickshell-wra`, so that never matches and every reload stacked a new bar.
  # `quickshell kill -p` only kills one instance per call; loop until none remain.
  hyprQuickshellReload = pkgs.writeShellScriptBin "qs-quickshell-reload" ''
    set -eu
    QS="${lib.getExe pkgs.quickshell}"
    SRC="${quickshellLiveDir}"
    SETSID="${lib.getExe' pkgs.util-linux "setsid"}"
    SLEEP="${lib.getExe' pkgs.coreutils "sleep"}"
    PKILL="${lib.getExe' pkgs.procps "pkill"}"
    PGREP="${lib.getExe' pkgs.procps "pgrep"}"
    GREP="${lib.getExe' pkgs.gnugrep "grep"}"

    if [ "''${QS_RELOAD_WORKER:-}" != 1 ]; then
      exec "$SETSID" -f env QS_RELOAD_WORKER=1 "$0"
    fi

    n=0
    while "$QS" list -p "$SRC" --any-display 2>/dev/null | "$GREP" -q '^Instance '; do
      "$QS" kill -p "$SRC" --any-display || true
      n=$((n + 1))
      if [ "$n" -ge 20 ]; then
        break
      fi
      "$SLEEP" 0.05
    done

    # Fallback: match cmdline `-p <live dir>` (comm name is not "quickshell").
    "$PKILL" -TERM -f -- "-p $SRC" || true
    n=0
    while "$PGREP" -f -- "-p $SRC" >/dev/null 2>&1; do
      n=$((n + 1))
      if [ "$n" -ge 25 ]; then
        "$PKILL" -KILL -f -- "-p $SRC" || true
        break
      fi
      "$SLEEP" 0.1
    done
    "$SLEEP" 0.2
    exec "$QS" -d -p "$SRC"
  '';
}

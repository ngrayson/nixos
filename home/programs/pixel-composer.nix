# Pixel Composer on Tawa: a capture harness (`pxc-debug`) and a version-explicit
# launcher (`pxc-launch`).
#
# Why a harness rather than ad-hoc `hyprctl` calls. Pixel Composer is a
# GameMaker (YoYo) app running under XWayland, and its popups -- file dialog,
# splash, error dialogs -- are separate transient X11 toplevels that carry the
# SAME title as the main window. `hyprctl clients` lists only MAPPED windows,
# so a popup that maps and unmaps quickly (the reported "flicker") never
# appears there at all. Diagnosing that needs the X11 tree polled and
# Hyprland's event socket tailed at the same time, with a way for a human to
# say "it happened, now" -- which is what `pxc-debug mark` is for.
#
# This module ships no fixes. Each symptom is its own card and gets a fix only
# once the harness has actually reproduced it.
{pkgs, ...}: let
  # The AppImage is the PRIMARY target. It was long believed broken; it was
  # not, it was invisible -- Hyprland placed its window at x=-1200, entirely
  # left of every output, which is fixed by the `monitor DP-1` anchor in
  # home/wayland/hyprland.nix. Being a native Linux build with no Wine layer
  # between it and the compositor, it is the cleaner surface for the four
  # window-management symptom cards. Steam/Proton is reachable with `--attach`.
  pxcLaunch = pkgs.writeShellApplication {
    name = "pxc-launch";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      set -euo pipefail

      # Resolve the build explicitly instead of hard-coding a version in the
      # desktop entry, which silently drifted from what was actually in ~/bin.
      # PXC_APPIMAGE wins so a specific build can be tested without editing Nix.
      img="''${PXC_APPIMAGE:-}"
      if [ -z "$img" ]; then
        # Newest by version, not by mtime: a re-downloaded older build must not
        # outrank a newer one.
        img="$(find "$HOME/bin" -maxdepth 1 -name 'Pixel_Composer_*-x86_64.AppImage' -print 2>/dev/null | sort -V | tail -1)"
      fi
      if [ -z "$img" ] || [ ! -f "$img" ]; then
        echo "pxc-launch: no Pixel Composer AppImage found in ~/bin (set PXC_APPIMAGE to override)" >&2
        exit 1
      fi
      exec /run/current-system/sw/bin/appimage-run "$img" "$@"
    '';
  };

  pxcDebug = pkgs.writeShellApplication {
    name = "pxc-debug";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
      pkgs.xwininfo
      pkgs.xprop
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
      pkgs.procps
      # pxc-debug execs pxc-launch for the appimage path. Declared rather than
      # relying on the ambient PATH, so the harness works before a switch has
      # put pxc-launch in the profile.
      pxcLaunch
      # NOT pkgs.netcat -- that resolves to LibreSSL's nc, which does not
      # advertise -U here. The Hyprland event socket is a unix socket, so the
      # OpenBSD build is the one that works.
      pkgs.netcat-openbsd
    ];
    text = ''
      set -euo pipefail

      ROOT="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pxc-debug"
      DISP="''${DISPLAY:-:1}"
      # Both Pixel Composer builds. The Steam/Proton window carries a real
      # WM_CLASS; the AppImage's is empty, which is why the AppImage is matched
      # on title and popups cannot be told apart from the main window by class.
      # Anchored, for matching hyprctl's `title` FIELD.
      TITLE_RE='^Pixel Composer|^Select files| - Pixel Composer'
      # Unanchored, for grepping xwininfo -tree OUTPUT LINES, which begin with
      # whitespace and the window id -- `0x6800003 "Pixel Composer 1.21.0": ...`
      # -- so an anchored pattern matches nothing. Getting this wrong silently
      # produced an EMPTY x11-tree.log for the AppImage while every other
      # collector worked, which is the one window this harness exists to watch.
      #
      # The class is matched too, and that is not redundant: the STEAM build's
      # popups do not carry the app's name at all. Measured 2026-09-10, its
      # splash maps as title "Window" and settles as "dialog" --
      #     0x5e00004 "dialog": ("steam_app_2299510" "steam_app_2299510")  1280x800
      # -- so a title-only filter saw 1 line where the class filter saw 18, and
      # the popup this harness exists to capture was among the 17 it missed.
      X11_RE='Pixel Composer|Select files|steam_app_2299510'
      STEAM_CLASS='steam_app_2299510'

      newest_run() {
        find "$ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1
      }

      # Every Pixel Composer window X11 knows about, mapped or not. This is the
      # source of truth for popups; hyprctl cannot see an unmapped window.
      x11_snapshot() {
        local ids id
        ids="$(xwininfo -display "$DISP" -root -tree 2>/dev/null | grep -E "$X11_RE" || true)"
        [ -n "$ids" ] || return 0
        printf '%s\n' "$ids"
        printf '%s\n' "$ids" | grep -o '0x[0-9a-f]*' | while IFS= read -r id; do
          printf -- '--- %s ---\n' "$id"
          xwininfo -display "$DISP" -id "$id" 2>/dev/null \
            | grep -E 'Map State|Override Redirect|Absolute upper-left|Width:|Height:' || true
          xprop -display "$DISP" -id "$id" \
            WM_TRANSIENT_FOR WM_NORMAL_HINTS _NET_WM_WINDOW_TYPE _NET_WM_STATE 2>/dev/null || true
        done
      }

      clients_snapshot() {
        hyprctl -j clients 2>/dev/null | jq -S -c \
          --arg re "$TITLE_RE" --arg cls "$STEAM_CLASS" \
          '[.[] | select(((.title // "") | test($re)) or ((.class // "") == $cls))
                | {address, title, class, at, size, floating, focusHistoryID,
                   fullscreen, monitor, workspace: .workspace.id, xwayland}]' 2>/dev/null || true
      }

      # Append only when the value CHANGED. A 250 ms poll that logged every
      # sample would bury the one transition that matters in thousands of
      # identical lines.
      watch_diff() {
        local out="$1" fn="$2" prev="" cur
        while :; do
          cur="$($fn)"
          if [ "$cur" != "$prev" ]; then
            {
              printf '=== %s ===\n' "$(date +%s.%N)"
              printf '%s\n' "$cur"
            } >>"$out"
            prev="$cur"
          fi
          sleep 0.25
        done
      }

      cmd_start() {
        local mode="''${1:-appimage}" attach="''${2:-}"
        local run sig sock
        run="$ROOT/$(date +%Y%m%dT%H%M%S)"
        mkdir -p "$run"

        {
          echo "launch_path: $mode''${attach:+ (attach)}"
          echo "started: $(date -Is)"
          echo "display: $DISP"
          hyprctl version 2>/dev/null | head -1
          echo "--- monitors ---"
          hyprctl -j monitors 2>/dev/null \
            | jq -c '.[] | {name, x, y, width, height, transform, scale, focused}' || true
          echo "--- options ---"
          for opt in general:resize_on_border general:extend_border_grab_area \
                     decoration:rounding input:follow_mouse; do
            printf '%s = %s\n' "$opt" "$(hyprctl -j getoption "$opt" 2>/dev/null | jq -r '.int // .str // .custom // "?"')"
          done
          echo "submap: $(hyprctl submap 2>/dev/null || echo unknown)"
          if [ "$mode" = appimage ]; then
            echo "appimage: $(find "$HOME/bin" -maxdepth 1 -name 'Pixel_Composer_*-x86_64.AppImage' -print 2>/dev/null | sort -V | tail -1)"
          else
            echo "steam_buildid: $(grep -o '\"buildid\"[^0-9]*[0-9]*' "$HOME/.local/share/Steam/steamapps/appmanifest_2299510.acf" 2>/dev/null | grep -o '[0-9]*$' | tail -1 || echo unknown)"
          fi
        } >"$run/meta.txt" 2>&1

        : >"$run/hypr-events.log"
        : >"$run/x11-tree.log"
        : >"$run/clients.log"
        : >"$run/pids"

        sig="''${HYPRLAND_INSTANCE_SIGNATURE:-}"
        sock="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$sig/.socket2.sock"
        if [ -n "$sig" ] && [ -S "$sock" ]; then
          (
            nc -U "$sock" \
              | grep --line-buffered -E 'openwindow|closewindow|movewindow|windowtitle|activewindow|changefloatingmode|submap|focusedmon' \
              | while IFS= read -r line; do printf '%s %s\n' "$(date +%s.%N)" "$line"; done >>"$run/hypr-events.log"
          ) >/dev/null 2>&1 &
          echo "$!" >>"$run/pids"
        else
          echo "WARNING: no Hyprland event socket at $sock -- events will not be captured" >&2
        fi

        # >/dev/null 2>&1 on every collector is load-bearing, not tidiness. A
        # background job inherits this script's stdout, and holding that pipe
        # open means `pxc-debug start | anything` never returns even though the
        # collectors are up and working. Found by smoke-testing before ship.
        watch_diff "$run/x11-tree.log" x11_snapshot >/dev/null 2>&1 &
        echo "$!" >>"$run/pids"
        watch_diff "$run/clients.log" clients_snapshot >/dev/null 2>&1 &
        echo "$!" >>"$run/pids"

        if [ "$mode" = appimage ]; then
          ( tail -F "$HOME/PixelComposer/log/log.txt" >>"$run/pc-log.txt" 2>/dev/null ) >/dev/null 2>&1 &
          echo "$!" >>"$run/pids"
        else
          ( tail -F "$HOME/.local/share/Steam/steamapps/common/Pixel Composer/log_temp.txt" >>"$run/pc-log.txt" 2>/dev/null ) >/dev/null 2>&1 &
          echo "$!" >>"$run/pids"
        fi

        # Detached on purpose: `pxc-debug stop`, or Ctrl-C on this harness, must
        # never take Pixel Composer down with it.
        if [ "$attach" != "--attach" ]; then
          if [ "$mode" = appimage ]; then
            setsid -f pxc-launch >/dev/null 2>&1 || echo "WARNING: pxc-launch failed" >&2
          else
            setsid -f steam steam://rungameid/2299510 >/dev/null 2>&1 || echo "WARNING: steam launch failed" >&2
          fi
        fi

        echo "run dir: $run"
        echo "Reproduce the bug, then the instant it happens run:  pxc-debug mark <what you saw>"
      }

      cmd_mark() {
        local run n dir
        run="$(newest_run)"
        [ -n "$run" ] || { echo "pxc-debug: no run to mark; start one first" >&2; exit 1; }
        n="$(( $(find "$run" -maxdepth 1 -type d -name 'mark-*' 2>/dev/null | wc -l) + 1 ))"
        dir="$run/mark-$n"
        mkdir -p "$dir"
        printf '%s  mark-%s  %s\n' "$(date +%s.%N)" "$n" "$*" >>"$run/marks.log"
        hyprctl -j clients >"$dir/clients.json" 2>/dev/null || true
        hyprctl -j activewindow >"$dir/activewindow.json" 2>/dev/null || true
        hyprctl cursorpos >"$dir/cursorpos.txt" 2>/dev/null || true
        hyprctl submap >"$dir/submap.txt" 2>/dev/null || true
        xwininfo -display "$DISP" -root -tree >"$dir/x11-tree-full.txt" 2>/dev/null || true
        echo "marked $n in $run"
      }

      cmd_stop() {
        local run pid
        run="$(newest_run)"
        [ -n "$run" ] || { echo "pxc-debug: no run to stop" >&2; exit 1; }
        if [ -f "$run/pids" ]; then
          while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            kill "$pid" 2>/dev/null || true
          done <"$run/pids"
        fi
        echo "collectors stopped; Pixel Composer left running"
      }

      # Output is meant to be pasted into a Conveyor card, so home paths and
      # anything under ~/Documents are stripped here rather than trusted to the
      # person pasting it.
      cmd_report() {
        local run
        run="''${1:-$(newest_run)}"
        [ -n "$run" ] || { echo "pxc-debug: no run to report" >&2; exit 1; }
        {
          echo "## pxc-debug report"
          echo
          echo '```'
          cat "$run/meta.txt" 2>/dev/null || true
          echo '```'
          echo
          if [ -f "$run/marks.log" ]; then
            echo "### Marks"
            echo '```'
            cat "$run/marks.log"
            echo '```'
            echo
            while IFS= read -r line; do
              local ts
              ts="$(printf '%s' "$line" | awk '{print $1}')"
              echo "#### $(printf '%s' "$line" | cut -d' ' -f3-)"
              for f in hypr-events.log x11-tree.log clients.log; do
                echo "\`$f\` around the mark:"
                echo '```'
                awk -v t="$ts" '
                  # x11-tree.log and clients.log group records under a
                  # `=== <epoch> ===` header; hypr-events.log timestamps every
                  # line instead. Track whichever this file uses -- keying only
                  # off the first line silently emptied the events slice.
                  /^=== / { s = $2 + 0; next }
                  ($1 + 0) > 1000000000 { s = $1 + 0 }
                  { if (s >= t - 5 && s <= t + 5) print }
                ' "$run/$f" 2>/dev/null | head -40 || true
                echo '```'
              done
              echo
            done <"$run/marks.log"
          else
            echo "_No marks recorded._"
          fi
        } | sed -e "s|$HOME|~|g" -e "/Documents/d"
      }

      case "''${1:-}" in
        start)  shift; cmd_start "$@" ;;
        mark)   shift; cmd_mark "$@" ;;
        stop)   shift; cmd_stop "$@" ;;
        report) shift; cmd_report "$@" ;;
        *)
          cat >&2 <<'USAGE'
      pxc-debug start [appimage|steam] [--attach]   capture a session (appimage is the primary target)
      pxc-debug mark <what you saw>                 timestamp the moment a bug happened, with a full snapshot
      pxc-debug stop                                stop collectors; Pixel Composer keeps running
      pxc-debug report [run-dir]                    Markdown summary, home paths stripped, safe to paste on a card
      USAGE
          exit 2
          ;;
      esac
    '';
  };
in {
  home.packages = [pxcDebug pxcLaunch];
}

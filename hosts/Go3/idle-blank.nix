# Blank the Go3 wall panel after 10 minutes with no input; wake on any input.
# Display power only — the kiosk never suspends, Chromium keeps running and
# the dashboard stays live and reachable throughout (hosts/Go3/README.md).
#
# Protocol-agnostic on purpose. cage is a deliberately minimal wlroots
# compositor and does not advertise the Wayland idle-notify or
# output-power-management protocols that swayidle/wlopm drive, so this works
# below the compositor instead: libinput for "was there input", and the kernel
# backlight interface for "is the panel lit".
#
# Verified on the machine 2026-09-01: the panel is `intel_backlight`
# (max_brightness 7500), /dev/input/event* is `root:input` 0660 so `wiz` reads
# events by group, and brightness was 0644 root:root with no udev rule -- hence
# the rule below.
{pkgs, ...}: let
  backlight = "/sys/class/backlight/intel_backlight";
  # Shared with the ambient-light service: we publish `state`, it
  # publishes `level`. A directory rather than two files directly in /run
  # because an atomic write renames *into* the directory, so the directory
  # itself has to be writable -- the same trap that bit the Hearth ledger.
  stateDir = "/run/go3-display";

  go3-idle-blank = pkgs.writeShellApplication {
    name = "go3-idle-blank";
    runtimeInputs = [pkgs.coreutils pkgs.libinput];
    text = ''
      set -euo pipefail

      # Overridable so the logic can be exercised against a scratch directory
      # off-box; the unit sets none of these and gets the real panel.
      BACKLIGHT="''${GO3_BACKLIGHT:-${backlight}}"
      DIM_SECONDS="''${GO3_DIM_SECONDS:-180}"
      # Measured from last input, not from entering dim -- so off lands 7
      # minutes after the dim, not 10 minutes after it.
      OFF_SECONDS="''${GO3_OFF_SECONDS:-''${GO3_IDLE_SECONDS:-600}}"
      DIM_FRACTION="''${GO3_DIM_FRACTION:-0.2}"
      STATE_DIR="''${GO3_STATE_DIR:-${stateDir}}"
      # Event source too, so the state machine can be driven by a scripted
      # stream in a test rather than by touching a physical panel.
      read -r -a EVENT_CMD <<<"''${GO3_EVENT_CMD:-libinput debug-events}"

      bright="$BACKLIGHT/brightness"
      maxfile="$BACKLIGHT/max_brightness"
      state_file="$STATE_DIR/state"
      level_file="$STATE_DIR/level"

      if [[ ! -w "$bright" ]]; then
        echo "go3-idle-blank: $bright is not writable; is the ExecStartPre grant applied?" >&2
        exit 1
      fi

      max="$(cat "$maxfile")"
      # awake | dim | off
      stage=awake
      # Seeded from whatever the panel is set to now, and re-captured whenever
      # we leave awake, so a level someone chose survives a cycle.
      on_level="$(cat "$bright")"
      [[ "$on_level" -gt 0 ]] || on_level="$max"

      # Atomic, because the ambient-light service polls this while we write it.
      # Renaming into the directory is why the directory itself must be
      # writable by us, not just the file.
      publish_stage() {
        stage="$1"
        printf '%s\n' "$stage" >"$state_file.tmp" 2>/dev/null || return 0
        mv -f "$state_file.tmp" "$state_file" 2>/dev/null || true
      }

      # The awake level the ambient-light service wants, if it is running.
      # Falls back to our own captured level, so this script is fully
      # functional standalone whether or not that service ever exists.
      target_level() {
        local want
        if [[ -r "$level_file" ]]; then
          want="$(cat "$level_file" 2>/dev/null || true)"
          if [[ "$want" =~ ^[0-9]+$ ]] && [[ "$want" -gt 0 ]] && [[ "$want" -le "$max" ]]; then
            printf '%s' "$want"
            return 0
          fi
        fi
        [[ "$on_level" -gt 0 ]] || on_level="$max"
        printf '%s' "$on_level"
      }

      # Recapture before leaving awake, so a manually-set brightness is what we
      # dim from and come back to.
      capture_on_level() {
        local current
        current="$(cat "$bright")"
        [[ "$current" -gt 0 ]] && on_level="$current"
      }

      dim() {
        capture_on_level
        local level
        # Floored, and never 0 -- 0 is the separate "off" stage, and a dim
        # panel has to stay visibly lit.
        level="$(awk -v o="$on_level" -v f="$DIM_FRACTION" 'BEGIN { v = int(o * f); if (v < 1) v = 1; print v }')"
        echo "$level" >"$bright"
        publish_stage dim
      }

      off() {
        [[ "$stage" == "awake" ]] && capture_on_level
        echo 0 >"$bright"
        publish_stage off
      }

      wake() {
        target_level >"$bright"
        publish_stage awake
      }

      # Restore on the way out from dim or off, but never when already awake.
      # A stopped or crashed unit must not leave a wall display dark or dim --
      # and equally must not stomp a brightness it never changed, which is what
      # made every deploy jump the panel to full.
      trap 'if [[ "$stage" != "awake" ]]; then wake; fi' EXIT

      publish_stage awake

      # libinput prints one line per input event -- key, touch, pointer -- from
      # the udev backend, independent of any compositor. `read -t` doing double
      # duty as the idle timer is the whole design: a line means input, a
      # timeout means the stage has expired.
      while true; do
        case "$stage" in
          awake) wait_for="$DIM_SECONDS" ;;
          dim)   wait_for="$((OFF_SECONDS - DIM_SECONDS))" ;;
          # Nothing left to time out into; block until input.
          *)     wait_for=0 ;;
        esac

        if [[ "$wait_for" -gt 0 ]]; then
          read -r -t "$wait_for" _line && rc=0 || rc=$?
        else
          read -r _line && rc=0 || rc=$?
        fi

        if [[ "$rc" -eq 0 ]]; then
          # Input at any stage goes straight back to full, never via dim.
          [[ "$stage" != "awake" ]] && wake
          continue
        fi
        # read(1) returns >128 on timeout and non-zero at EOF; only a real
        # timeout advances a stage, EOF means libinput died and the loop ends.
        if [[ "$rc" -le 128 ]]; then
          echo "go3-idle-blank: input stream closed" >&2
          exit 1
        fi
        case "$stage" in
          awake) dim ;;
          dim)   off ;;
        esac
      done < <("''${EVENT_CMD[@]}")
    '';
  };
in {
  # Persistent across restarts of either service, so the ambient-light
  # service can keep writing `level` while this one is being restarted.
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0775 wiz video -"
  ];

  systemd.services.go3-idle-blank = {
    description = "Blank the Go3 kiosk panel after idle, wake on input";
    # Deliberately independent of cage-tty1. Tying the two together looked
    # right -- the blanker watches the kiosk's panel -- but it is not: this
    # writes the kernel backlight, which the compositor does not own and which
    # works whether or not cage is running.
    #
    # The coupling cost two deploy failures. BindsTo made a cage stop kill this
    # unit; adding `wantedBy = cage-tty1.service` to bring it back put a
    # symlink in cage-tty1.service.wants/, so editing THIS file changed
    # cage-tty1's dependencies too -- switch-to-configuration then restarted
    # cage (restartIfChanged), which SIGTERMed this unit mid-start and left
    # the wall blank for a minute. A change to the blanker must not restart
    # the kiosk.
    #
    # `after` is kept purely for boot ordering; Restart=always is what keeps
    # this alive now, rather than another unit's lifecycle.
    after = ["cage-tty1.service"];
    wantedBy = ["graphical.target"];
    serviceConfig = {
      # The panel is root-owned 0644, so nothing but root can dim it. A udev
      # rule was the obvious grant and was wrong: udev rules fire on device
      # events, and the backlight is added at boot, so on a live switch the
      # rule never ran and the service crash-looped on an unwritable file
      # (observed 2026-09-01). Doing it here instead runs immediately before
      # the service needs it, on every start, independent of udev timing.
      #
      # Still the same narrow grant programs.light makes -- group `video`
      # gains write on backlight brightness and nothing else, and `wiz` is
      # already in `video`. The `+` prefix runs these as root; the unit body
      # runs as `wiz`, who cannot chgrp.
      ExecStartPre = [
        "+${pkgs.coreutils}/bin/chgrp video ${backlight}/brightness"
        "+${pkgs.coreutils}/bin/chmod g+w ${backlight}/brightness"
      ];
      ExecStart = "${go3-idle-blank}/bin/go3-idle-blank";
      User = "wiz";
      # Reading /dev/input/event* is group `input`; writing brightness is
      # group `video` via the udev rule above.
      SupplementaryGroups = ["input" "video"];
      Restart = "always";
      RestartSec = "5s";
    };
  };
}

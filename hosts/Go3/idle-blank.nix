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

  go3-idle-blank = pkgs.writeShellApplication {
    name = "go3-idle-blank";
    runtimeInputs = [pkgs.coreutils pkgs.libinput];
    text = ''
      set -euo pipefail

      # Overridable so the logic can be exercised against a scratch directory
      # off-box; the unit sets neither and gets the real panel.
      BACKLIGHT="''${GO3_BACKLIGHT:-${backlight}}"
      IDLE_SECONDS="''${GO3_IDLE_SECONDS:-600}"
      # Event source too, so the blank/wake state machine can be driven by a
      # scripted stream in a test rather than by touching a physical panel.
      read -r -a EVENT_CMD <<<"''${GO3_EVENT_CMD:-libinput debug-events}"

      bright="$BACKLIGHT/brightness"
      maxfile="$BACKLIGHT/max_brightness"

      if [[ ! -w "$bright" ]]; then
        echo "go3-idle-blank: $bright is not writable; is the udev rule applied?" >&2
        exit 1
      fi

      max="$(cat "$maxfile")"
      blanked=0
      # Seeded from whatever the panel is set to now, and re-captured on each
      # blank, so a level someone chose survives a blank/wake cycle.
      on_level="$(cat "$bright")"
      [[ "$on_level" -gt 0 ]] || on_level="$max"

      blank() {
        local current
        current="$(cat "$bright")"
        if [[ "$current" -gt 0 ]]; then
          on_level="$current"
        fi
        echo 0 >"$bright"
        blanked=1
      }

      wake() {
        [[ "$on_level" -gt 0 ]] || on_level="$max"
        echo "$on_level" >"$bright"
        blanked=0
      }

      # Restore on the way out, but only if we are the reason the panel is
      # dark. A stopped or crashed blanker must never leave a wall display
      # off -- and equally must not touch a brightness it never changed:
      # restoring unconditionally made every deploy (which stops this unit)
      # write on_level over the current level, jumping the panel to full.
      trap 'if [[ "$blanked" -eq 1 ]]; then wake; fi' EXIT

      # libinput prints one line per input event -- key, touch, pointer -- from
      # the udev backend, independent of any compositor. `read -t` doing double
      # duty as the idle timer is the whole design: a line means input, a
      # timeout means idle.
      while true; do
        if read -r -t "$IDLE_SECONDS" _line; then
          if [[ "$blanked" -eq 1 ]]; then
            wake
          fi
        else
          # read(1) returns >128 on timeout and non-zero at EOF; only a real
          # timeout should blank, EOF means libinput died and the loop ends.
          status=$?
          if [[ "$status" -le 128 ]]; then
            echo "go3-idle-blank: input stream closed" >&2
            exit 1
          fi
          if [[ "$blanked" -eq 0 ]]; then
            blank
          fi
        fi
      done < <("''${EVENT_CMD[@]}")
    '';
  };
in {
  systemd.services.go3-idle-blank = {
    description = "Blank the Go3 kiosk panel after idle, wake on input";
    # Tied to the session it dims: no point watching for input with no kiosk,
    # and a cage restart (deploys restart it) should cycle this too.
    after = ["cage-tty1.service"];
    bindsTo = ["cage-tty1.service"];
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

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
      # Captured fresh each time we blank, so a brightness someone changed
      # while the panel was awake survives a blank/wake cycle.
      on_level="$max"

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

      # Restore the panel on the way out: a stopped or crashed blanker must
      # never be the reason a wall display stays dark.
      trap 'wake || true' EXIT

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
  # The panel is root-owned 0644 by default, so nothing but root can dim it.
  # This is the same narrow grant programs.light and hardware.brillo make:
  # group `video` gains write on backlight brightness and nothing else. `wiz`
  # is already in `video` (profiles/kiosk.nix), so no sudo widening is needed.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/backlight/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/backlight/%k/brightness"
  '';

  systemd.services.go3-idle-blank = {
    description = "Blank the Go3 kiosk panel after idle, wake on input";
    # Tied to the session it dims: no point watching for input with no kiosk,
    # and a cage restart (deploys restart it) should cycle this too.
    after = ["cage-tty1.service"];
    bindsTo = ["cage-tty1.service"];
    wantedBy = ["graphical.target"];
    serviceConfig = {
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

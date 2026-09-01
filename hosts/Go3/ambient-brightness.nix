# Set the kiosk's awake brightness from its ambient light sensor.
#
# Confirmed on the machine: /sys/bus/iio/devices/iio:device5 is name `als`,
# with in_illuminance_raw and in_illuminance_scale 0.001, readable 0644. The
# device number is NOT hardcoded -- it is found by reading `name`, since IIO
# numbering is not stable across boots.
#
# The sensor intermittently returns a spurious 0. Measured in an unchanging
# dark hallway: 3120 3120 3120 0 0 3120 3120 3120 -- a quarter of the reads.
# Taken at face value that would drop the panel to minimum and back several
# times a minute, so every poll takes a median of several samples instead of
# one reading.
#
# Ownership of the panel is shared with go3-idle-blank via the files in
# /run/go3-display: that service owns `state`, this one owns `level`. While
# the state is dim or off the panel belongs to the blanker and this service
# only refreshes `level`, so a wake lands on a current value rather than a
# stale one.
{pkgs, ...}: let
  backlight = "/sys/class/backlight/intel_backlight";
  stateDir = "/run/go3-display";

  go3-ambient-brightness = pkgs.writeShellApplication {
    name = "go3-ambient-brightness";
    runtimeInputs = [pkgs.coreutils pkgs.gawk];
    text = ''
      set -euo pipefail

      BACKLIGHT="''${GO3_BACKLIGHT:-${backlight}}"
      STATE_DIR="''${GO3_STATE_DIR:-${stateDir}}"
      IIO_ROOT="''${GO3_IIO_ROOT:-/sys/bus/iio/devices}"
      POLL_SECONDS="''${GO3_ALS_POLL_SECONDS:-5}"
      # Odd, so the median is a real sample rather than an average of two.
      SAMPLES="''${GO3_ALS_SAMPLES:-5}"
      # Ignore changes smaller than this fraction of max, so the panel is not
      # visibly hunting between neighbouring levels all day.
      DEADBAND_FRACTION="''${GO3_ALS_DEADBAND:-0.02}"
      # Never go fully dark from ambient light; that is the blanker's job.
      FLOOR_FRACTION="''${GO3_ALS_FLOOR:-0.12}"

      bright="$BACKLIGHT/brightness"
      state_file="$STATE_DIR/state"
      level_file="$STATE_DIR/level"
      max="$(cat "$BACKLIGHT/max_brightness")"

      find_als() {
        local dir
        for dir in "$IIO_ROOT"/iio:device*; do
          [[ -r "$dir/name" ]] || continue
          [[ "$(cat "$dir/name")" == "als" ]] || continue
          [[ -r "$dir/in_illuminance_raw" ]] || continue
          printf '%s' "$dir"
          return 0
        done
        return 1
      }

      als="$(find_als || true)"
      if [[ -z "$als" ]]; then
        echo "go3-ambient-brightness: no IIO device named 'als'" >&2
        exit 1
      fi
      scale=1
      [[ -r "$als/in_illuminance_scale" ]] && scale="$(cat "$als/in_illuminance_scale")"

      # The defence against the driver's intermittent zeros: a zero is only
      # believed when EVERY sample is zero. Otherwise the median of the
      # non-zero samples wins.
      #
      # A plain median is not enough. Measured against a sensor emitting
      # roughly a third spurious zeros, median-of-5 still collapsed the panel
      # to the floor on a quarter of polls, because three bad samples can land
      # in one 500ms window. Genuine darkness reads zero on all of them, so
      # unanimity is the honest test.
      read_lux() {
        local i vals=() nonzero=()
        for ((i = 0; i < SAMPLES; i++)); do
          vals+=("$(cat "$als/in_illuminance_raw" 2>/dev/null || echo 0)")
          ((i < SAMPLES - 1)) && sleep 0.1
        done
        for v in "''${vals[@]}"; do
          [[ "$v" =~ ^[0-9]+$ ]] && [[ "$v" -gt 0 ]] && nonzero+=("$v")
        done
        if [[ "''${#nonzero[@]}" -eq 0 ]]; then
          printf '0'
          return 0
        fi
        printf '%s\n' "''${nonzero[@]}" | sort -n | \
          awk -v n="''${#nonzero[@]}" -v s="$scale" \
            'NR == int((n + 1) / 2) { printf "%.3f", $1 * s }'
      }

      # Piecewise-linear lux to fraction-of-max. Deliberately coarse and
      # tunable rather than a tuned curve guessed from a datasheet.
      level_for_lux() {
        awk -v lux="$1" -v max="$max" -v floor="$FLOOR_FRACTION" 'BEGIN {
          split("0 5 50 200 1000 5000", lx, " ");
          split("0.12 0.15 0.35 0.60 0.85 1.00", fr, " ");
          f = fr[6];
          for (i = 1; i < 6; i++) {
            if (lux <= lx[i + 1]) {
              span = lx[i + 1] - lx[i];
              t = (span > 0) ? (lux - lx[i]) / span : 0;
              f = fr[i] + t * (fr[i + 1] - fr[i]);
              break;
            }
          }
          if (f < floor) f = floor;
          v = int(max * f);
          if (v < 1) v = 1;
          print v;
        }'
      }

      publish_level() {
        printf '%s\n' "$1" >"$level_file.tmp" 2>/dev/null || return 0
        mv -f "$level_file.tmp" "$level_file" 2>/dev/null || true
      }

      while true; do
        lux="$(read_lux)"
        want="$(level_for_lux "$lux")"
        publish_level "$want"

        # Only the blanker touches the panel while it is dim or off. Keeping
        # `level` fresh anyway is what makes a wake land on the right value.
        state=awake
        [[ -r "$state_file" ]] && state="$(cat "$state_file" 2>/dev/null || echo awake)"
        if [[ "$state" == "awake" ]] && [[ -w "$bright" ]]; then
          current="$(cat "$bright")"
          if awk -v a="$current" -v b="$want" -v m="$max" -v d="$DEADBAND_FRACTION" \
               'BEGIN { exit !((a > b ? a - b : b - a) > m * d) }'; then
            echo "$want" >"$bright"
          fi
        fi
        sleep "$POLL_SECONDS"
      done
    '';
  };
in {
  systemd.services.go3-ambient-brightness = {
    description = "Set the Go3 kiosk brightness from its ambient light sensor";
    # Deliberately not bound to cage-tty1, for the reason recorded in
    # idle-blank.nix: coupling a backlight service to the compositor's
    # lifecycle made every deploy restart the kiosk.
    after = ["go3-idle-blank.service"];
    wantedBy = ["graphical.target"];
    serviceConfig = {
      # Same narrow grant idle-blank makes, and idempotent alongside it: this
      # unit must not depend on that one having started first.
      ExecStartPre = [
        "+${pkgs.coreutils}/bin/chgrp video ${backlight}/brightness"
        "+${pkgs.coreutils}/bin/chmod g+w ${backlight}/brightness"
      ];
      ExecStart = "${go3-ambient-brightness}/bin/go3-ambient-brightness";
      User = "wiz";
      SupplementaryGroups = ["video"];
      Restart = "always";
      RestartSec = "5s";
    };
  };
}

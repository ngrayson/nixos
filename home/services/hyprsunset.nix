# f.lux-style screen warmth: hyprsunset does the gamma writing, this module
# does the scheduling.
#
# Why not hyprsunset's own `profile` entries: they are fixed wall-clock
# cutovers. They cannot ramp, they know nothing about sunrise/sunset, and they
# do not re-apply after a suspend/resume (the daemon keeps whatever it last
# set). The scheduler below is a 30-second idempotent tick instead, which gets
# smoothing, geolocation and suspend-recovery for free: every tick recomputes
# the target from the clock and pushes it only when it differs.
#
# Why not gammastep/wlsunset: wlr-gamma is proven dead on Tawa's outputs --
# "Zero outputs support gamma adjustment" on AMD Navi 22/amdgpu/Hyprland
# 0.55.4, ruled out as a competing gamma client. See PR #173/#174 and the
# card `add-gammastep-for-automatic-screen-warmth-by-sunrise-sunset`.
#
# HARD CONSTRAINT: hyprsunset must be the ONLY colour-transform-matrix writer.
# Two CTM writers fight and the screen flickers between them. Nothing else in
# this repo may touch gamma, and the Quickshell bar deliberately talks to the
# control script rather than calling `hyprctl hyprsunset` itself.
{
  config,
  lib,
  pkgs,
  ...
}: let
  tickSec = 30;

  # Defaults, overridable at runtime from the bar's modal (settings.json).
  dayTemp = 6500;
  nightTemp = 3400;
  dayGamma = 100;
  nightGamma = 90;
  # Minutes before sunset/sunrise that the ramp begins.
  transitionMin = 45;
  # Seconds to ease over when something changes discretely -- a toggle, a
  # pause, a settings edit -- rather than because the clock moved. 0 disables
  # the ease and restores the old instant push.
  discreteRampSec = 5;

  stateHome = "\${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr-sunset";
  confHome = "\${XDG_CONFIG_HOME:-$HOME/.config}/hypr-sunset";

  # Split in two on purpose: writeShellApplication runs shellcheck, and a
  # script that loads settings it never reads fails SC2034. The control script
  # only needs the paths.
  dirsPreamble = ''
    STATE_DIR="''${HYPR_SUNSET_STATE_DIR:-${stateHome}}"
    CONF_DIR="''${HYPR_SUNSET_CONFIG_DIR:-${confHome}}"
    mkdir -p "$STATE_DIR" "$CONF_DIR"
    SETTINGS="$CONF_DIR/settings.json"
    OVERRIDE="$STATE_DIR/override.json"
    STATE="$STATE_DIR/state.json"

    [ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"
    [ -f "$OVERRIDE" ] || echo '{}' >"$OVERRIDE"
  '';

  # jq's // also swallows `false`, which would be wrong for a boolean; every
  # key here is a number, so // is safe and keeps a hand-edited partial
  # settings file working instead of erroring.
  settingsPreamble = ''
    read_setting() { jq -r --argjson d "$2" ".$1 // \$d" "$SETTINGS"; }
    DAY_TEMP="$(read_setting dayTemp ${toString dayTemp})"
    NIGHT_TEMP="$(read_setting nightTemp ${toString nightTemp})"
    DAY_GAMMA="$(read_setting dayGamma ${toString dayGamma})"
    NIGHT_GAMMA="$(read_setting nightGamma ${toString nightGamma})"
    TRANSITION_MIN="$(read_setting transitionMin ${toString transitionMin})"
    DISCRETE_RAMP_SEC="$(read_setting discreteRampSec ${toString discreteRampSec})"
  '';

  hyprSunsetApply = pkgs.writeShellApplication {
    name = "hypr-sunset-apply";
    runtimeInputs = [pkgs.coreutils pkgs.jq pkgs.sunwait pkgs.gawk pkgs.hyprland];
    text = ''
      set -euo pipefail

      ${dirsPreamble}
      ${settingsPreamble}

      # Test hooks. The unit sets none of these; they exist so the whole
      # schedule can be exercised against a scratch tree at an arbitrary
      # clock, without a compositor and without touching the real screen.
      NOW="''${HYPR_SUNSET_NOW:-$(date +%s)}"
      HYPRCTL="''${HYPR_SUNSET_HYPRCTL:-${pkgs.hyprland}/bin/hyprctl}"

      # --- ramp mode -------------------------------------------------------
      # `--ramp` eases from the CURRENT live value to the computed target
      # instead of pushing once. hypr-sunset-ctl uses it for every discrete
      # change; the 30s timer never does, because the natural sunrise/sunset
      # transition already ramps across its own window.
      RAMP_MODE=0
      [ "''${1:-}" = "--ramp" ] && RAMP_MODE=1
      RAMPFILE="$STATE_DIR/ramp.pid"

      # A ramp owns the screen for a few seconds. The tick must not push its
      # clock-derived value in the middle of one -- that value IS the ramp's
      # endpoint, so a tick landing mid-ramp snaps straight to the end.
      #
      # Staleness matters more than the race: if this returned true whenever
      # the file merely existed, one dead PID would make every future tick
      # skip and freeze the screen at a fixed colour, silently and forever.
      # That is a far worse failure than the snap this ramp removes.
      ramp_active() {
        local pid
        [ -f "$RAMPFILE" ] || return 1
        pid="$(cat "$RAMPFILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
          return 0
        fi
        rm -f "$RAMPFILE"
        return 1
      }

      # Rapid clicking must not leave two ramps interleaving pushes.
      disarm_ramp() {
        local pid
        if [ -f "$RAMPFILE" ]; then
          pid="$(cat "$RAMPFILE" 2>/dev/null || true)"
          [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
          rm -f "$RAMPFILE"
        fi
      }

      # The one easing curve, used for both the natural transition and the
      # discrete ramp. Slow at both ends, quick through the middle -- a linear
      # ramp reads as a start and a stop.
      ease_between() {
        awk -v a="$1" -v b="$2" -v p="$3" \
          'BEGIN{e=p*p*(3-2*p); printf "%d", a+(b-a)*e}'
      }

      # --- location ------------------------------------------------------
      # A hand-written CONF_DIR/location.json always wins and geoclue is never
      # consulted -- that is the escape hatch for a machine where geoclue is
      # unavailable or wrong. Otherwise seed STATE_DIR/location.json once and
      # cache it: a 30s tick must not hammer geoclue, and coordinates are
      # personal data that must never reach this public repo.
      LOCATION=""
      if [ -f "$CONF_DIR/location.json" ]; then
        LOCATION="$CONF_DIR/location.json"
      elif [ -f "$STATE_DIR/location.json" ]; then
        LOCATION="$STATE_DIR/location.json"
      else
        if raw="$(timeout 20 ${pkgs.geoclue2}/libexec/geoclue-2.0/demos/where-am-i -t 15 2>/dev/null)"; then
          lat="$(printf '%s\n' "$raw" | awk '/^Latitude:/  {gsub(/°/,"",$2); print $2; exit}')"
          lon="$(printf '%s\n' "$raw" | awk '/^Longitude:/ {gsub(/°/,"",$2); print $2; exit}')"
          if [ -n "$lat" ] && [ -n "$lon" ]; then
            umask 077
            jq -n --argjson lat "$lat" --argjson lon "$lon" \
              '{lat: $lat, lon: $lon}' >"$STATE_DIR/location.json"
            LOCATION="$STATE_DIR/location.json"
          fi
        fi
      fi

      if [ -z "$LOCATION" ]; then
        # No location yet. Do NOT guess and do NOT touch the screen -- leave
        # whatever is on it and try again next tick. Recorded in state.json so
        # the bar can say why the pill is idle instead of looking broken.
        jq -n '{ok: false, reason: "no-location"}' >"$STATE".tmp
        mv "$STATE".tmp "$STATE"
        exit 0
      fi

      LAT="$(jq -r '.lat' "$LOCATION")"
      LON="$(jq -r '.lon' "$LOCATION")"

      # sunwait wants unsigned degrees with a hemisphere letter, geoclue gives
      # signed decimals.
      LATA="$(awk -v v="$LAT" 'BEGIN{printf "%.6f%s", (v<0?-v:v), (v<0?"S":"N")}')"
      LONA="$(awk -v v="$LON" 'BEGIN{printf "%.6f%s", (v<0?-v:v), (v<0?"W":"E")}')"

      # --- sun times -----------------------------------------------------
      # `sunwait list 1` prints "HH:MM, HH:MM" (rise, set) in local time.
      TIMES="$(sunwait list 1 "$LATA" "$LONA" 2>/dev/null || true)"
      RISE_HM="$(printf '%s' "$TIMES" | awk -F', *' '{print $1}' | tr -d ' ')"
      SET_HM="$(printf '%s' "$TIMES" | awk -F', *' '{print $2}' | tr -d ' ')"

      # Polar day/night makes sunwait print something that is not a time.
      if ! printf '%s' "$RISE_HM" | grep -qE '^[0-9]{1,2}:[0-9]{2}$' \
        || ! printf '%s' "$SET_HM" | grep -qE '^[0-9]{1,2}:[0-9]{2}$'; then
        jq -n '{ok: false, reason: "no-sun-times"}' >"$STATE".tmp
        mv "$STATE".tmp "$STATE"
        exit 0
      fi

      DAY0="$(date -d "@$NOW" +%Y-%m-%d)"
      RISE="$(date -d "$DAY0 $RISE_HM" +%s)"
      SET="$(date -d "$DAY0 $SET_HM" +%s)"

      # --- override ------------------------------------------------------
      # NOT `.enabled // true`: jq's // treats false as empty, so that form
      # reads a disabled state back as enabled and the toggle never works.
      ENABLED="$(jq -r 'if .enabled == false then "false" else "true" end' "$OVERRIDE")"
      DISABLED_UNTIL="$(jq -r '.disabledUntil // 0' "$OVERRIDE")"

      SUPPRESSED=0
      if [ "$ENABLED" != "true" ]; then
        SUPPRESSED=1
      elif [ "$DISABLED_UNTIL" -gt "$NOW" ] 2>/dev/null; then
        SUPPRESSED=1
      elif [ "$DISABLED_UNTIL" -ne 0 ] 2>/dev/null; then
        # Timed disable has elapsed; clear it so the file does not accumulate
        # stale epochs and the bar stops showing a countdown.
        jq '.disabledUntil = 0' "$OVERRIDE" >"$OVERRIDE".tmp && mv "$OVERRIDE".tmp "$OVERRIDE"
        DISABLED_UNTIL=0
      fi

      # --- target --------------------------------------------------------
      # Ramp runs from (event - TRANSITION_MIN) to the event itself, matching
      # the "x minutes before sunset/sunrise" setting the bar exposes.
      RAMP=$((TRANSITION_MIN * 60))
      SET_START=$((SET - RAMP))
      RISE_START=$((RISE - RAMP))

      # progress: 0.0 = fully day, 1.0 = fully night.
      if [ "$SUPPRESSED" -eq 1 ]; then
        PHASE="off"
        PROGRESS=0
      elif [ "$NOW" -ge "$SET" ] || [ "$NOW" -lt "$RISE_START" ]; then
        PHASE="night"
        PROGRESS=1
      elif [ "$NOW" -ge "$SET_START" ]; then
        PHASE="to-night"
        PROGRESS="$(awk -v n="$NOW" -v s="$SET_START" -v r="$RAMP" 'BEGIN{printf "%.4f", (n-s)/r}')"
      elif [ "$NOW" -lt "$RISE" ]; then
        PHASE="to-day"
        PROGRESS="$(awk -v n="$NOW" -v s="$RISE_START" -v r="$RAMP" 'BEGIN{printf "%.4f", 1-((n-s)/r)}')"
      else
        PHASE="day"
        PROGRESS=0
      fi

      TEMP="$(ease_between "$DAY_TEMP" "$NIGHT_TEMP" "$PROGRESS")"
      GAMMA="$(ease_between "$DAY_GAMMA" "$NIGHT_GAMMA" "$PROGRESS")"

      # --- next event (published for the bar) ------------------------------
      NEXT_EVENT="$SET"
      NEXT_KIND="sunset"
      if [ "$NOW" -ge "$SET" ] || [ "$NOW" -lt "$RISE" ]; then
        NEXT_KIND="sunrise"
        if [ "$NOW" -ge "$SET" ]; then
          NEXT_EVENT=$((RISE + 86400))
        else
          NEXT_EVENT="$RISE"
        fi
      fi

      # $1 temp, $2 gamma, $3 ramping (true|false). Written on every ramp step,
      # not just at the end: the pill's number moving is half of why the ease
      # exists -- it makes the transition observable on demand instead of only
      # at dusk. Atomic rename, so the bar never reads a half-written file.
      publish_state() {
        # Per-writer temp name: a ramp and a tick (or two ramps racing during
        # a disarm) sharing one "$STATE".tmp lose each other's writes and one
        # of them fails the mv outright.
        local tmp="$STATE.tmp.$BASHPID"
        jq -n \
          --argjson ok true \
          --arg phase "$PHASE" \
          --argjson temp "$1" \
          --argjson gamma "$2" \
          --argjson ramping "$3" \
          --argjson dayTemp "$DAY_TEMP" \
          --argjson nightTemp "$NIGHT_TEMP" \
          --argjson dayGamma "$DAY_GAMMA" \
          --argjson nightGamma "$NIGHT_GAMMA" \
          --argjson transitionMin "$TRANSITION_MIN" \
          --argjson sunrise "$RISE" \
          --argjson sunset "$SET" \
          --argjson nextEvent "$NEXT_EVENT" \
          --arg nextKind "$NEXT_KIND" \
          --argjson enabled "$([ "$ENABLED" = "true" ] && echo true || echo false)" \
          --argjson disabledUntil "$DISABLED_UNTIL" \
          --argjson now "$NOW" \
          '{ok: $ok, phase: $phase, temp: $temp, gamma: $gamma, ramping: $ramping,
            dayTemp: $dayTemp, nightTemp: $nightTemp,
            dayGamma: $dayGamma, nightGamma: $nightGamma,
            transitionMin: $transitionMin,
            sunrise: $sunrise, sunset: $sunset,
            nextEvent: $nextEvent, nextKind: $nextKind,
            enabled: $enabled, disabledUntil: $disabledUntil, now: $now}' \
          >"$tmp"
        mv "$tmp" "$STATE"
      }

      # --- apply -----------------------------------------------------------
      # Only push when the value actually differs, so a 30s tick is not 2880
      # daily CTM rewrites. A failed read means "unknown", which pushes.
      CUR_TEMP="$("$HYPRCTL" hyprsunset temperature 2>/dev/null | tr -dc '0-9' || true)"
      CUR_GAMMA="$("$HYPRCTL" hyprsunset gamma 2>/dev/null | awk -F. '{print $1}' | tr -dc '0-9' || true)"

      if [ "$RAMP_MODE" -eq 1 ]; then
        disarm_ramp
        # No "from" value means no ramp: hyprsunset is not up yet, so easing
        # from an unknown start is meaningless. Same for a zero-length ramp and
        # for a target we are already sitting on. All three fall through to the
        # single push below, which is exactly the old behaviour.
        if [ -n "$CUR_TEMP" ] && [ -n "$CUR_GAMMA" ] \
          && [ "$DISCRETE_RAMP_SEC" -gt 0 ] \
          && { [ "$CUR_TEMP" != "$TEMP" ] || [ "$CUR_GAMMA" != "$GAMMA" ]; }; then
          (
            # Remove the lock only if it is still OURS. A newer ramp disarms us
            # and writes its own PID here; without this guard our dying trap
            # would delete the new ramp's lock and let ticks fight it.
            trap 'if [ "$(cat "$RAMPFILE" 2>/dev/null || true)" = "$BASHPID" ]; then rm -f "$RAMPFILE"; fi' EXIT
            # TERM/INT must EXIT, not merely run a handler. A trap that only
            # cleans up leaves the loop running afterwards, so disarm_ramp's
            # kill is swallowed and two ramps interleave their pushes -- seen
            # for real before this line existed. The EXIT trap still fires.
            trap 'exit 143' TERM
            trap 'exit 130' INT

            steps=$((DISCRETE_RAMP_SEC * 4))
            [ "$steps" -lt 1 ] && steps=1
            for i in $(seq 1 "$steps"); do
              sleep 0.25
              p="$(awk -v i="$i" -v n="$steps" 'BEGIN{printf "%.4f", i/n}')"
              t="$(ease_between "$CUR_TEMP" "$TEMP" "$p")"
              g="$(ease_between "$CUR_GAMMA" "$GAMMA" "$p")"
              "$HYPRCTL" hyprsunset temperature "$t" >/dev/null 2>&1 || true
              "$HYPRCTL" hyprsunset gamma "$g" >/dev/null 2>&1 || true
              publish_state "$t" "$g" true
            done
            # Land exactly on the target rather than on the last eased step.
            "$HYPRCTL" hyprsunset temperature "$TEMP" >/dev/null 2>&1 || true
            "$HYPRCTL" hyprsunset gamma "$GAMMA" >/dev/null 2>&1 || true
            publish_state "$TEMP" "$GAMMA" false
          ) &
          echo $! >"$RAMPFILE"
          exit 0
        fi
      elif ramp_active; then
        # Mid-ramp. Skip the push AND the state write: the ramp's endpoint is
        # the value this tick would apply anyway, and it is publishing its own
        # intermediate state. One skipped 30s tick costs nothing.
        exit 0
      fi

      if [ "$CUR_TEMP" != "$TEMP" ]; then
        "$HYPRCTL" hyprsunset temperature "$TEMP" >/dev/null 2>&1 || true
      fi
      if [ "$CUR_GAMMA" != "$GAMMA" ]; then
        "$HYPRCTL" hyprsunset gamma "$GAMMA" >/dev/null 2>&1 || true
      fi

      publish_state "$TEMP" "$GAMMA" false
    '';
  };

  hyprSunsetCtl = pkgs.writeShellApplication {
    name = "hypr-sunset-ctl";
    runtimeInputs = [pkgs.coreutils pkgs.jq];
    text = ''
      set -euo pipefail

      ${dirsPreamble}

      NOW="''${HYPR_SUNSET_NOW:-$(date +%s)}"

      write_override() { jq "$1" "$OVERRIDE" >"$OVERRIDE".tmp && mv "$OVERRIDE".tmp "$OVERRIDE"; }
      write_setting() { jq "$1" "$SETTINGS" >"$SETTINGS".tmp && mv "$SETTINGS".tmp "$SETTINGS"; }

      case "''${1:-}" in
        toggle)
          # See the note in hypr-sunset-apply: `// true` would swallow false.
          cur="$(jq -r 'if .enabled == false then "false" else "true" end' "$OVERRIDE")"
          if [ "$cur" = "true" ]; then
            write_override '.enabled = false | .disabledUntil = 0'
          else
            write_override '.enabled = true | .disabledUntil = 0'
          fi
          ;;
        enable)
          write_override '.enabled = true | .disabledUntil = 0'
          ;;
        disable)
          # `disable <seconds>` for a timed pause, or `disable sunrise`.
          arg="''${2:-}"
          if [ "$arg" = "sunrise" ]; then
            until_epoch="$(jq -r '.nextEvent // 0' "$STATE" 2>/dev/null || echo 0)"
            kind="$(jq -r '.nextKind // ""' "$STATE" 2>/dev/null || echo "")"
            # nextEvent is only the sunrise when that is what is next; if the
            # sun has not set yet, the next sunrise is the following morning.
            if [ "$kind" != "sunrise" ]; then
              until_epoch="$(jq -r '(.sunrise // 0) + 86400' "$STATE" 2>/dev/null || echo 0)"
            fi
            write_override ".enabled = true | .disabledUntil = $until_epoch"
          elif printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
            write_override ".enabled = true | .disabledUntil = $((NOW + arg))"
          else
            echo "usage: hypr-sunset-ctl disable <seconds>|sunrise" >&2
            exit 2
          fi
          ;;
        set)
          key="''${2:-}"
          val="''${3:-}"
          case "$key" in
            dayTemp | nightTemp | dayGamma | nightGamma | transitionMin) ;;
            *)
              echo "hypr-sunset-ctl set: unknown key '$key'" >&2
              exit 2
              ;;
          esac
          printf '%s' "$val" | grep -qE '^[0-9]+$' || {
            echo "hypr-sunset-ctl set: '$val' is not a non-negative integer" >&2
            exit 2
          }
          write_setting ".$key = $val"
          ;;
        *)
          echo "usage: hypr-sunset-ctl {toggle|enable|disable <seconds>|sunrise|set <key> <value>}" >&2
          exit 2
          ;;
      esac

      # Re-apply immediately rather than making the user wait out the tick, and
      # ease into it rather than snapping -- every subcommand above is a
      # discrete change, which is exactly what --ramp is for.
      ${lib.getExe hyprSunsetApply} --ramp || true
    '';
  };
in {
  # hyprsunset itself: the daemon only, with no profiles. The scheduler above
  # owns every value it ever holds. --identity so a fresh start is a no-op
  # until the first tick, rather than snapping to the 6000K built-in default.
  services.hyprsunset = {
    enable = true;
    extraArgs = ["--identity"];
  };

  home.packages = [hyprSunsetApply hyprSunsetCtl];

  systemd.user.services.hypr-sunset = {
    Unit = {
      Description = "Apply scheduled screen warmth via hyprsunset";
      After = ["hyprsunset.service"];
      PartOf = [config.wayland.systemd.target];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe hyprSunsetApply;
    };
  };

  systemd.user.timers.hypr-sunset = {
    Unit.Description = "Screen warmth tick";
    Timer = {
      OnStartupSec = "10s";
      OnUnitActiveSec = "${toString tickSec}s";
      AccuracySec = "5s";
      # Resume from suspend lands mid-schedule; without this the first tick
      # after waking waits out the full interval with yesterday's colour.
      Persistent = false;
    };
    Install.WantedBy = ["timers.target"];
  };
}

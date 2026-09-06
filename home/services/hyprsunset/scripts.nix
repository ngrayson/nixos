# The hyprsunset scheduler scripts, extracted so they can be built and tested
# WITHOUT evaluating a whole Home Manager / NixOS closure. `home/services/
# hyprsunset.nix` imports this and wires the results into the user session; the
# `hypr-sunset-tests` check in `flake.nix` imports the same `apply`/`ctl` and
# drives them against a scratch tree with a stub `hyprctl`. Because both sides
# import ONE definition, a green `nix flake check` proves the exact scripts the
# session runs still behave.
#
# HARD CONSTRAINT (see AGENTS.md "Screen warmth"): hyprsunset must be the ONLY
# colour-transform-matrix writer. Nothing here may be duplicated into a second
# gamma client, and the bar talks to `hypr-sunset-ctl`, never `hyprctl
# hyprsunset` directly.
{
  pkgs,
  lib,
}: let
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
  #
  # Responsiveness comes from the change STARTING immediately, not from
  # finishing quickly, so this is deliberately long.
  discreteRampSec = 10;
  # Milliseconds between ramp steps. Kept separate from the duration above
  # because the two tune opposite things: duration is how the ease FEELS,
  # interval is what it COSTS. The old code hardcoded `steps = sec * 4`, which
  # welded them together -- a longer ease could only be bought with more
  # pushes per second. 10s at 500ms is the same 20 steps as the old 5s at
  # 250ms, at half the instantaneous rate.
  #
  # Do not raise much past 500ms without checking for banding: a 2000->6500K
  # sweep moves ~225K per step here, and coarser steps start to read as
  # stepping rather than a fade.
  rampStepMs = 500;

  # Preview: the "show me a night" demo the bar's modal triggers. Fade to
  # night over previewFadeSec, hold previewHoldSec, then fade back to whatever
  # was live before over previewFadeSec. Kept as two constants so the hold can
  # diverge from the fades later. Both are mirrored BY HAND in
  # quickshell/SunsetMenu.qml (previewFadeMs/previewHoldMs) -- there is no
  # shared source of truth between this bash script and the QML, and building
  # config-plumbing for two small numbers is not worth it.
  previewFadeSec = 5;
  previewHoldSec = 5;

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
    RAMP_STEP_MS="$(read_setting rampStepMs ${toString rampStepMs})"
    # Floor it: 0 would divide by zero computing the step count, and anything
    # below a frame is pointless work.
    [ "$RAMP_STEP_MS" -lt 50 ] && RAMP_STEP_MS=50
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

      # --- push log (correlation) -----------------------------------------
      # One line per REAL hyprsunset write: `epoch temp gamma <tick|ramp|
      # preview>`. This is what turns "I felt a hitch at 19:52 in-game" into
      # "yes, a push happened at 19:52:04". Only actual writes reach log_push --
      # the tick's `!=` guards and fade_between's byte-identical skip keep
      # read-only ticks out of it, so the log is a faithful record of CTM
      # commits, not of timer fires. The timestamp uses bash's printf %()T
      # builtin (no `date` fork); the file is trimmed to the last 500 lines
      # once per tick (not per ramp step) so a long session cannot grow it
      # without bound.
      PUSHLOG="$STATE_DIR/pushes.log"
      log_push() {
        local ts
        printf -v ts '%(%s)T' -1
        printf '%s %s %s %s\n' "$ts" "$1" "$2" "$3" >>"$PUSHLOG"
      }
      trim_pushlog() {
        local n
        [ -f "$PUSHLOG" ] || return 0
        n="$(wc -l <"$PUSHLOG")"
        if [ "$n" -gt 500 ]; then
          tail -n 500 "$PUSHLOG" >"$PUSHLOG.tmp" && mv "$PUSHLOG.tmp" "$PUSHLOG"
        fi
      }

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

      # Ease temperature+gamma from one pair to another over DUR seconds,
      # pushing each step to hyprsunset. This is the step-table + push loop the
      # discrete ramp used to inline; the ramp and the preview fades now share
      # it rather than keeping two copies of the awk one-liner. $5 selects
      # whether to also write state.json each step: "publish" for the discrete
      # ramp (the pill's number moving is half of why the ease exists), "" for
      # preview (a transient demo that must not clobber the real schedule
      # number). $7 is the push-log kind ("ramp"|"preview"). Same smoothstep
      # curve and %d truncation as ease_between. Skips a push whose eased
      # integer did not move -- gamma spans only 90->100 across a whole sweep,
      # so consecutive steps are routinely byte-identical (measured 10 of 20),
      # and an identical push costs the same as a changed one.
      fade_between() {
        local from_t="$1" from_g="$2" to_t="$3" to_g="$4" pub="$5" dur="$6" kind="$7"
        local steps step_sleep last_t last_g t g pushed
        steps=$(((dur * 1000) / RAMP_STEP_MS))
        [ "$steps" -lt 1 ] && steps=1
        step_sleep="$(awk -v ms="$RAMP_STEP_MS" 'BEGIN{printf "%.3f", ms/1000}')"
        last_t="$from_t"
        last_g="$from_g"
        while read -r t g; do
          sleep "$step_sleep"
          pushed=0
          if [ "$t" != "$last_t" ]; then
            "$HYPRCTL" hyprsunset temperature "$t" >/dev/null 2>&1 || true
            last_t="$t"
            pushed=1
          fi
          if [ "$g" != "$last_g" ]; then
            "$HYPRCTL" hyprsunset gamma "$g" >/dev/null 2>&1 || true
            last_g="$g"
            pushed=1
          fi
          # Log only actual writes, and use `if` not `&&`: under set -e a
          # short-circuited `&&` leaves the loop body's status at 1 and aborts
          # the caller (same trap the publish_state guard below documents).
          if [ "$pushed" -eq 1 ]; then
            log_push "$t" "$g" "$kind"
          fi
          # `if`, not `&& publish_state`: the && form leaves the loop body's
          # exit status at 1 whenever pub is empty (preview), and under set -e
          # that aborts the caller right after the first fade -- the fade-back
          # never runs and the screen stays stuck at night.
          if [ -n "$pub" ]; then
            publish_state "$t" "$g" true
          fi
        done < <(awk -v ta="$from_t" -v tb="$to_t" \
          -v ga="$from_g" -v gb="$to_g" -v n="$steps" \
          'BEGIN{for(i=1;i<=n;i++){p=i/n; e=p*p*(3-2*p);
                 printf "%d %d\n", ta+(tb-ta)*e, ga+(gb-ga)*e}}')
      }

      # --- preview mode ----------------------------------------------------
      # A manual one-off demo from the bar's modal: fade to night, hold, fade
      # back to exactly what was live before. Deliberately ignores
      # enabled/disabled/suppressed state (it is a demo, not a schedule change)
      # and never writes state.json, so the pill keeps showing the real
      # schedule number throughout. Reuses the RAMPFILE lock so a 30s tick
      # cannot fight the fade, and returns BEFORE any geoclue/sun-time work --
      # preview needs none of it and must not trigger a geoclue call or a
      # "no-location" state write.
      if [ "''${1:-}" = "--preview" ]; then
        CUR_TEMP="$("$HYPRCTL" hyprsunset temperature 2>/dev/null | tr -dc '0-9' || true)"
        CUR_GAMMA="$("$HYPRCTL" hyprsunset gamma 2>/dev/null | awk -F. '{print $1}' | tr -dc '0-9' || true)"
        # Nothing to fade from if hyprsunset is not up yet.
        [ -n "$CUR_TEMP" ] && [ -n "$CUR_GAMMA" ] || exit 0

        disarm_ramp
        (
          # Same lock discipline as the discrete ramp: remove RAMPFILE only if
          # it is still ours, and make TERM/INT actually exit so a newer ramp
          # or preview cleanly takes over.
          trap 'if [ "$(cat "$RAMPFILE" 2>/dev/null || true)" = "$BASHPID" ]; then rm -f "$RAMPFILE"; fi' EXIT
          trap 'exit 143' TERM
          trap 'exit 130' INT

          fade_between "$CUR_TEMP" "$CUR_GAMMA" "$NIGHT_TEMP" "$NIGHT_GAMMA" "" ${toString previewFadeSec} preview
          sleep ${toString previewHoldSec}
          fade_between "$NIGHT_TEMP" "$NIGHT_GAMMA" "$CUR_TEMP" "$CUR_GAMMA" "" ${toString previewFadeSec} preview
        ) &
        echo $! >"$RAMPFILE"
        exit 0
      fi

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

            # Ease from the live value to the target, publishing each step so
            # the pill's number moves as it goes. The last eased step is
            # exactly the target, so hyprsunset already sits on it here.
            fade_between "$CUR_TEMP" "$CUR_GAMMA" "$TEMP" "$GAMMA" publish "$DISCRETE_RAMP_SEC" ramp
            # Final state write marks the ramp finished (ramping=false).
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

      PUSHED_TICK=0
      if [ "$CUR_TEMP" != "$TEMP" ]; then
        "$HYPRCTL" hyprsunset temperature "$TEMP" >/dev/null 2>&1 || true
        PUSHED_TICK=1
      fi
      if [ "$CUR_GAMMA" != "$GAMMA" ]; then
        "$HYPRCTL" hyprsunset gamma "$GAMMA" >/dev/null 2>&1 || true
        PUSHED_TICK=1
      fi
      # A push-per-tick only happens inside the two transition windows and at a
      # phase edge; steady day/night ticks are idempotent and log nothing.
      if [ "$PUSHED_TICK" -eq 1 ]; then
        log_push "$TEMP" "$GAMMA" tick
        trim_pushlog
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
        preview)
          # A one-off visual demo, not a settings/override change, so it must
          # NOT fall through to the trailing `--ramp` re-apply below (that would
          # snap the screen back the instant the fade started). exec replaces
          # this process so the tail-call never runs.
          exec ${lib.getExe hyprSunsetApply} --preview
          ;;
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
            # discreteRampSec was missing here since it shipped, so
            # `hypr-sunset-ctl set discreteRampSec 0` -- the documented way to
            # turn the ease off -- exited 2 with "unknown key".
            discreteRampSec | rampStepMs) ;;
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
          echo "usage: hypr-sunset-ctl {toggle|enable|disable <seconds>|sunrise|set <key> <value>|preview}" >&2
          exit 2
          ;;
      esac

      # Re-apply immediately rather than making the user wait out the tick, and
      # ease into it rather than snapping -- every subcommand above is a
      # discrete change, which is exactly what --ramp is for.
      ${lib.getExe hyprSunsetApply} --ramp || true
    '';
  };

  # --- Layer 2: live frame-time benchmark ------------------------------------
  # Correlates real gamma/temperature pushes with frame-time spikes under a
  # bounded Vulkan workload, so "the sunset tool causes lag in games" can be
  # measured instead of felt. It A/Bs `render:ctm_animation` (auto -> on for
  # AMD; every CTM push is faded over several DRM commits, the prime suspect).
  #
  # NOT run by any timer or by CI -- this is shellcheck-gated only (it changes
  # screen warmth and opens a window, so it is Nick's to run, with him present,
  # after an `os-rebuild switch`). It obeys the single-writer rule by STOPPING
  # `hypr-sunset.timer` for its run and being the only `hyprctl hyprsunset`
  # writer meanwhile, and it restores temperature, gamma, `render:ctm_animation`
  # and the timer on EVERY exit path including Ctrl-C.
  hyprSunsetBench = pkgs.writeShellApplication {
    name = "hypr-sunset-bench";
    runtimeInputs = [
      pkgs.mangohud
      pkgs.vulkan-tools
      pkgs.hyprland
      pkgs.jq
      pkgs.gawk
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      STATE_DIR="''${HYPR_SUNSET_STATE_DIR:-${stateHome}}"
      BENCH_DIR="$STATE_DIR/bench"
      RUN_TS="$(date +%Y%m%dT%H%M%S)"
      OUT="$BENCH_DIR/$RUN_TS"
      mkdir -p "$OUT"

      # vkcube frames per pass. ~3000 at 60fps is ~50s -- it must outlast
      # LOG_SECONDS below (MangoHud only flushes the CSV when the log duration
      # elapses, not when vkcube exits), and cover the 5s baseline + push
      # sequence. run_pass kills vkcube once the CSV lands, so a larger count is
      # only a safety margin, never wasted wall time.
      FRAMES="''${1:-3000}"

      # MangoHud logging window per pass. Long enough for the 5s baseline plus
      # the ~20s push sequence, and SHORTER than the vkcube run so the duration
      # elapses mid-run and MangoHud writes the CSV (it does not flush an
      # in-progress log when the app exits).
      LOG_SECONDS=28
      # autostart_log delays logging this many seconds after vkcube launches, so
      # MangoHud elapsed=0 lands ~AUTOSTART_SEC after the vk-start mark. analyze
      # subtracts it when mapping push marks onto the frame log.
      AUTOSTART_SEC=1

      cat <<EOF
      hypr-sunset-bench: this will VISIBLY change screen warmth for ~30s and
      open a vkcube window. It stops hypr-sunset.timer, A/Bs
      render:ctm_animation (on vs off), and restores temperature, gamma,
      ctm_animation and the timer when it finishes -- including on Ctrl-C.
      Output: $OUT
      EOF

      # --- save state we are about to touch --------------------------------
      ORIG_TEMP="$(hyprctl hyprsunset temperature 2>/dev/null | tr -dc '0-9' || true)"
      ORIG_GAMMA="$(hyprctl hyprsunset gamma 2>/dev/null | awk -F. '{print $1}' | tr -dc '0-9' || true)"
      ORIG_CTM="$(hyprctl getoption render:ctm_animation -j 2>/dev/null | jq -r '.int // 2' || echo 2)"
      TIMER_WAS_ACTIVE=0
      if systemctl --user is-active --quiet hypr-sunset.timer; then
        TIMER_WAS_ACTIVE=1
      fi

      restore() {
        # Best-effort, order does not matter; each guarded so one failure does
        # not skip the rest. Restoring ctm_animation first means the final
        # temp/gamma writes land under the user's real setting.
        hyprctl keyword render:ctm_animation "$ORIG_CTM" >/dev/null 2>&1 || true
        if [ -n "$ORIG_TEMP" ]; then
          hyprctl hyprsunset temperature "$ORIG_TEMP" >/dev/null 2>&1 || true
        fi
        if [ -n "$ORIG_GAMMA" ]; then
          hyprctl hyprsunset gamma "$ORIG_GAMMA" >/dev/null 2>&1 || true
        fi
        if [ "$TIMER_WAS_ACTIVE" -eq 1 ]; then
          systemctl --user start hypr-sunset.timer >/dev/null 2>&1 || true
        fi
        # Hand ownership straight back to the scheduler so the screen is correct
        # for the current clock without waiting out a tick.
        hypr-sunset-apply >/dev/null 2>&1 || true
      }
      trap restore EXIT
      trap 'exit 143' TERM
      trap 'exit 130' INT

      # Single-writer: the scheduler must not push while we own the screen.
      systemctl --user stop hypr-sunset.timer >/dev/null 2>&1 || true

      # A scripted, timestamped push sequence: a raw temperature write, a gamma
      # write, a byte-identical repeat (should be skipped/cheap), then a full
      # --ramp ease. Timestamps go to the per-pass marks file so the analysis
      # can line each push up against the frame-time log.
      push_sequence() {
        # Appends to $marks; run_pass truncates it and writes the vk-start
        # anchor first, so the anchor is never clobbered here.
        local marks="$1" t
        t=6500; hyprctl hyprsunset temperature "$t" >/dev/null 2>&1 || true
        printf '%s temp %s\n' "$(date +%s.%N)" "$t" >>"$marks"; sleep 3
        hyprctl hyprsunset gamma 90 >/dev/null 2>&1 || true
        printf '%s gamma 90\n' "$(date +%s.%N)" >>"$marks"; sleep 3
        # identical repeat -- hyprsunset still processes it; this measures the
        # cost of a no-op push.
        hyprctl hyprsunset gamma 90 >/dev/null 2>&1 || true
        printf '%s gamma-repeat 90\n' "$(date +%s.%N)" >>"$marks"; sleep 3
        printf '%s ramp-start\n' "$(date +%s.%N)" >>"$marks"
        hypr-sunset-apply --ramp >/dev/null 2>&1 || true
        sleep 6
        printf '%s ramp-end\n' "$(date +%s.%N)" >>"$marks"
      }

      # Parse a MangoHud CSV (frametime column in ms, elapsed column in ns since
      # the log started) plus the per-pass marks file, and print one pass's JSON:
      # overall p50/p99/max, the first-5s baseline p99, and a `pushes` array
      # correlating each scripted push against the frame log -- the max frametime
      # inside the push window and how many frames there exceeded 2x the baseline
      # p99. Hard-fails with exit 2 when no CSV or no frametime rows were
      # captured, so summary.json can never carry a null pass again.
      #
      # MangoHud writes two metadata lines, then a header row naming the columns,
      # then data. The header is located by name, not by position.
      analyze_pass() {
        local csv="$1" marks="$2" label="$3" dir="$4" json
        if [ -z "$csv" ] || [ ! -f "$csv" ]; then
          echo "hypr-sunset-bench: $label captured no MangoHud CSV under $dir" >&2
          echo "  the MangoHud Vulkan layer never loaded into vkcube; see $dir/vkcube.log" >&2
          exit 2
        fi
        # A `local json="$(...)"` on one line would mask the command's exit
        # status (local always returns 0); declare first, assign separately, so
        # the `|| exit 2` below actually fires when gawk reports no rows.
        json="$(gawk -F, -v marksfile="$marks" -v autostart="$AUTOSTART_SEC" '
          BEGIN {
            # Marks are "<epoch> <name> [value]". vk-start is the t0 anchor that
            # maps MangoHud elapsed (ns from log start) onto push wall-clock.
            while ((getline line < marksfile) > 0) {
              split(line, a, " ")
              if (a[2] == "vk-start")  { t0 = a[1]; continue }
              if (a[2] == "ramp-start") rs = a[1]
              if (a[2] == "ramp-end")   re = a[1]
              nm++; mname[nm] = a[2]; mts[nm] = a[1]
            }
          }
          !cols {
            for (i = 1; i <= NF; i++) {
              g = $i; gsub(/[" ]/, "", g)
              if (g == "frametime") ftc = i
              if (g == "elapsed")   elc = i
            }
            if (ftc) cols = 1
            next
          }
          ftc && ($ftc + 0) > 0 {
            fv = $ftc + 0
            # A frametime over 1s is not a real frame: under a fullscreen game
            # the vkcube window is intermittently occluded and MangoHud logs the
            # whole gap-until-next-present as one enormous frametime (~9.4e8 ms
            # observed). Count and drop these so a single artifact cannot become
            # max_ms or skew p99/baseline. A real hitch, even a severe stall,
            # stays well under this cap.
            if (fv > 1000) { garbage++; next }
            n++
            ft[n] = fv
            el[n] = (elc ? $elc + 0 : 0)
            v[n] = fv
            if (fv > mx) mx = fv
            # Baseline = the quiet stretch before the first push. The first push
            # (temp) lands ~4s into the log (5s after vk-start, minus autostart),
            # so 3.5s of log stays clear of it.
            if (el[n] < 3.5e9) { bn++; bv[bn] = fv }
          }
          END {
            if (!n) exit 3
            asort(v)
            p50 = v[int(n * 0.50) < 1 ? 1 : int(n * 0.50)]
            p99 = v[int(n * 0.99) < 1 ? 1 : int(n * 0.99)]
            bp99 = 0
            if (bn) { asort(bv); bp99 = bv[int(bn * 0.99) < 1 ? 1 : int(bn * 0.99)] }
            thr = 2 * bp99
            pushes = ""
            for (m = 1; m <= nm; m++) {
              if (mname[m] == "ramp-end") continue
              # Map each mark onto log-elapsed: subtract t0 (vk-start) AND the
              # autostart delay (logging began that much after the anchor). +/-
              # 300ms absorbs residual skew; pushes are 3s apart, so windows
              # never overlap, and the ramp is its own start..end span.
              if (mname[m] == "ramp-start") {
                lo = (rs - t0 - autostart) * 1e9; hi = (re - t0 - autostart) * 1e9; name = "ramp"
              } else {
                c = (mts[m] - t0 - autostart) * 1e9; lo = c - 300e6; hi = c + 300e6; name = mname[m]
              }
              wmax = 0; over = 0
              for (k = 1; k <= n; k++) {
                if (el[k] >= lo && el[k] <= hi) {
                  if (ft[k] > wmax) wmax = ft[k]
                  if (thr > 0 && ft[k] > thr) over++
                }
              }
              if (pushes != "") pushes = pushes ","
              pushes = pushes sprintf("{\"name\":\"%s\",\"max_ms\":%.3f,\"frames_over_2x_baseline_p99\":%d}", name, wmax, over)
            }
            printf "{\"frames\":%d,\"garbage_frames\":%d,\"p50_ms\":%.3f,\"p99_ms\":%.3f,\"max_ms\":%.3f,\"baseline_p99_ms\":%.3f,\"pushes\":[%s]}", n, garbage, p50, p99, mx, bp99, pushes
          }
        ' "$csv")" || {
          echo "hypr-sunset-bench: $label MangoHud CSV ($csv) has no frametime rows; see $dir/vkcube.log" >&2
          exit 2
        }
        printf '%s' "$json"
      }

      run_pass() {
        # $1 label, $2 ctm_animation value
        local label="$1" ctm="$2" dir marks csv vk
        dir="$OUT/$label"
        marks="$OUT/$label.marks"
        mkdir -p "$dir"
        hyprctl keyword render:ctm_animation "$ctm" >/dev/null 2>&1 || true

        # Three things the original launch got wrong, each of which alone left
        # the capture empty (all observed on Tawa 2026-09-05):
        #   1. bare MANGOHUD=1 does not inject the layer on NixOS -- use the
        #      mangohud WRAPPER, which puts the manifest on the loader's path.
        #   2. no_display suppresses the log entirely, not just the overlay -- so
        #      it is gone; the overlay showing during a manual bench is fine.
        #   3. MangoHud flushes the CSV when log_duration ELAPSES, not when the
        #      app exits, so the window (LOG_SECONDS) is shorter than the vkcube
        #      run and we wait for the file rather than for every frame.
        # vkcube/loader output goes to vkcube.log so a failed capture is
        # diagnosable.
        MANGOHUD_CONFIG="output_folder=$dir,log_duration=$LOG_SECONDS,autostart_log=$AUTOSTART_SEC,log_interval=0" \
          mangohud vkcube --c "$FRAMES" >"$dir/vkcube.log" 2>&1 &
        vk=$!

        # Anchor the frame log to wall-clock. Truncate here, not in
        # push_sequence, so the anchor survives; analyze subtracts AUTOSTART_SEC
        # (logging starts that long after this mark) when placing the pushes.
        : >"$marks"
        printf '%s vk-start\n' "$(date +%s.%N)" >>"$marks"

        sleep 5 # baseline before any push
        push_sequence "$marks"

        # MangoHud writes the CSV when its log_duration elapses (~AUTOSTART_SEC +
        # LOG_SECONDS after launch), so wait for the file, then stop vkcube --
        # never wait out all FRAMES. Bounded so a capture that never lands still
        # returns and analyze_pass reports the hard failure. The _summary.csv is
        # a per-run rollup, not per-frame, so it is excluded.
        csv=""
        for _ in $(seq 1 30); do
          csv="$(find "$dir" -maxdepth 1 -name '*.csv' ! -name '*_summary.csv' -type f 2>/dev/null | sort | tail -n1)"
          [ -n "$csv" ] && break
          sleep 1
        done
        kill "$vk" 2>/dev/null || true
        wait "$vk" 2>/dev/null || true

        analyze_pass "$csv" "$marks" "$label" "$dir"
      }

      # A failed pass exits 2 from inside the command substitution; propagate it
      # (a plain assignment carries the substitution's status, unlike `local`),
      # so we never fall through and write a summary. The EXIT trap still runs
      # restore(), so temp/gamma/ctm/timer are put back on this path too.
      echo "Pass 1/2: render:ctm_animation = 1 (fade on)"
      ON_JSON="$(run_pass ctm-on 1)" || exit 2
      echo "Pass 2/2: render:ctm_animation = 0 (fade off)"
      OFF_JSON="$(run_pass ctm-off 0)" || exit 2

      SUMMARY="$OUT/summary.json"
      jq -n \
        --arg ts "$RUN_TS" \
        --argjson frames "$FRAMES" \
        --argjson on "$ON_JSON" \
        --argjson off "$OFF_JSON" \
        '{ts: $ts, frames: $frames, ctm_on: $on, ctm_off: $off}' >"$SUMMARY"

      echo
      echo "hypr-sunset-bench results ($RUN_TS)"
      echo "  pass       p50(ms)  p99(ms)  max(ms)  base-p99  garbage"
      jq -r '
        def row(l; o): "  \(l | . + "        " | .[0:9])"
          + ((o.p50_ms // 0 | tostring | . + "         " | .[0:9]))
          + ((o.p99_ms // 0 | tostring | . + "         " | .[0:9]))
          + ((o.max_ms // 0 | tostring | . + "         " | .[0:9]))
          + ((o.baseline_p99_ms // 0 | tostring | . + "         " | .[0:9]))
          + ((o.garbage_frames // 0 | tostring));
        row("ctm-on"; .ctm_on), row("ctm-off"; .ctm_off)
      ' "$SUMMARY"

      echo
      echo "  per-push max frametime and frames over 2x baseline p99:"
      echo "  pass     mark          max(ms)   >2x-base"
      jq -r '
        def prows(l; o): (o.pushes // [])[]
          | "  \(l | . + "        " | .[0:8]) "
            + "\(.name | . + "            " | .[0:12]) "
            + "\(.max_ms | tostring | . + "         " | .[0:8]) "
            + "\(.frames_over_2x_baseline_p99 | tostring)";
        prows("ctm-on"; .ctm_on), prows("ctm-off"; .ctm_off)
      ' "$SUMMARY"

      # If MangoHud logged occlusion artifacts, say so: they were dropped from
      # the numbers, but their presence means vkcube was not presenting cleanly,
      # so run the game WINDOWED (not fullscreen-exclusive) for a loaded pass.
      if [ "$(jq '[.ctm_on.garbage_frames, .ctm_off.garbage_frames] | add' "$SUMMARY")" -gt 0 ]; then
        echo
        echo "  note: dropped garbage frametimes (vkcube occluded, likely a"
        echo "        fullscreen game). Numbers above exclude them; run the game"
        echo "        windowed so vkcube keeps presenting for a clean loaded pass."
      fi
      echo
      echo "Full JSON + per-pass CSVs and push marks under: $OUT"
    '';
  };
in {
  apply = hyprSunsetApply;
  ctl = hyprSunsetCtl;
  bench = hyprSunsetBench;
}

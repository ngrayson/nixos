#!/usr/bin/env bash
# Deterministic script-level test suite for the hyprsunset scheduler
# (home/services/hyprsunset/scripts.nix). It drives the REAL hypr-sunset-apply
# / hypr-sunset-ctl against a scratch tree through the env hooks
# (HYPR_SUNSET_STATE_DIR / _CONFIG_DIR / _NOW / _HYPRCTL), with a stub `hyprctl`
# that records every write and answers reads from a small state file. Nothing
# here touches a compositor or a real screen, so it is safe to run anywhere and
# is wired into `nix flake check` as the `hypr-sunset-tests` check.
#
# It exercises what the scheduler PROMISES: pushes happen only inside the
# transition windows and during ramps (idempotent ticks push nothing), the
# ramp skips byte-identical steps, a tick landing mid-ramp is skipped, preview
# fades out and back without writing state.json, `.enabled == false` disables
# (the jq `//` bug would let it read back as enabled), and every real write is
# recorded in pushes.log.
#
# Binaries: `$HYPR_SUNSET_APPLY_BIN` / `$HYPR_SUNSET_CTL_BIN` if set (the flake
# check points them at freshly built scripts), else `hypr-sunset-apply` /
# `hypr-sunset-ctl` from PATH (a direct run on Tawa).
#
# Determinism: a FIXED clock (HYPR_SUNSET_NOW) plus a FIXED public-landmark
# location (New York City, 40.7128 / -74.0060 -- never Nick's coordinates) plus
# a FIXED timezone aligned to that location. The exact sunrise/sunset are read
# back out of the scheduler's own state.json rather than hardcoded, so the
# suite does not care what sunwait computes, only that the phase logic is
# consistent with it.
#
# The stub is `#!/bin/sh` on purpose: the nix build sandbox has no
# /usr/bin/env, so a `#!/usr/bin/env bash` stub would silently fail to exec and
# every hyprctl call would look like a no-op. Writes are counted from a
# dedicated writes-file rather than by parsing a timestamped log, so nothing
# depends on a bash-only feature inside the stub.

set -uo pipefail

export LC_ALL=C
# NYC coordinates want a US-Eastern clock, or sunset would wrap past midnight
# UTC and rise/set would misorder. tzdata + TZDIR come from the flake check;
# a direct run inherits the system's.
export TZ="${TZ:-America/New_York}"

APPLY="${HYPR_SUNSET_APPLY_BIN:-hypr-sunset-apply}"
CTL="${HYPR_SUNSET_CTL_BIN:-hypr-sunset-ctl}"
command -v "$APPLY" >/dev/null 2>&1 || {
  echo "hypr-sunset-tests: cannot find apply binary '$APPLY'" >&2
  exit 1
}
command -v "$CTL" >/dev/null 2>&1 || {
  echo "hypr-sunset-tests: cannot find ctl binary '$CTL'" >&2
  exit 1
}

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

STATE_DIR="$SCRATCH/state"
CONF_DIR="$SCRATCH/conf"
STUB_STATE="$SCRATCH/stub"
STUB_WRITES="$SCRATCH/writes.log"
mkdir -p "$STATE_DIR" "$CONF_DIR" "$STUB_STATE"
: >"$STUB_WRITES"
OVERRIDE="$STATE_DIR/override.json"
STATE="$STATE_DIR/state.json"

export HYPR_SUNSET_STATE_DIR="$STATE_DIR"
export HYPR_SUNSET_CONFIG_DIR="$CONF_DIR"

# Stub hyprctl: answers reads from STUB_STATE and appends one line per WRITE to
# STUB_WRITES ("temperature 3400" / "gamma 90"). Reads append nothing, so a
# line count of STUB_WRITES is exactly the push count. Absolute paths are baked
# in at creation; only $2/$3 stay dynamic.
STUB="$SCRATCH/hyprctl-stub"
cat >"$STUB" <<STUBEOF
#!/bin/sh
case "\${2:-}" in
  temperature)
    if [ -n "\${3:-}" ]; then printf '%s\n' "\$3" >"$STUB_STATE/temp"; printf 'temperature %s\n' "\$3" >>"$STUB_WRITES"
    else cat "$STUB_STATE/temp" 2>/dev/null || printf '6500\n'; fi ;;
  gamma)
    if [ -n "\${3:-}" ]; then printf '%s\n' "\$3" >"$STUB_STATE/gamma"; printf 'gamma %s\n' "\$3" >>"$STUB_WRITES"
    else cat "$STUB_STATE/gamma" 2>/dev/null || printf '100\n'; fi ;;
esac
STUBEOF
chmod +x "$STUB"
export HYPR_SUNSET_HYPRCTL="$STUB"

echo '{"lat":40.7128,"lon":-74.0060}' >"$CONF_DIR/location.json"

# --- helpers ---------------------------------------------------------------
FAILS=0
pass() { printf '  [PASS] %s\n' "$1"; }
fail() {
  printf '  [FAIL] %s\n' "$1"
  FAILS=$((FAILS + 1))
}
assert_eq() { # desc expected actual
  if [ "$2" = "$3" ]; then pass "$1 (= $2)"; else fail "$1: expected '$2', got '$3'"; fi
}
assert_ge() { # desc min actual
  if [ "$3" -ge "$2" ] 2>/dev/null; then pass "$1 (>= $2, got $3)"; else fail "$1: expected >= $2, got $3"; fi
}
assert_le() { # desc max actual
  if [ "$3" -le "$2" ] 2>/dev/null; then pass "$1 (<= $2, got $3)"; else fail "$1: expected <= $2, got $3"; fi
}

writes_total() { wc -l <"$STUB_WRITES" 2>/dev/null | tr -d ' '; }
# writes recorded strictly after write number $1
count_writes() { awk -v start="$1" 'NR>start{c++} END{print c+0}' "$STUB_WRITES"; }

stub_seed() {
  echo "$1" >"$STUB_STATE/temp"
  echo "$2" >"$STUB_STATE/gamma"
}
set_settings() { printf '%s' "$1" >"$CONF_DIR/settings.json"; }

reset_state() {
  rm -f "$STATE_DIR"/state.json "$STATE_DIR"/ramp.pid \
    "$STATE_DIR"/pushes.log "$STATE_DIR"/state.json.tmp* 2>/dev/null || true
  echo '{}' >"$OVERRIDE"
  set_settings '{}'
  : >"$STUB_WRITES"
}

run_apply() { # NOW [args...]
  local now="$1"
  shift
  HYPR_SUNSET_NOW="$now" "$APPLY" "$@"
}

# Ramps and previews fork a background subshell whose PID is written to
# ramp.pid; wait for it to finish (bounded).
wait_ramp() {
  local pid deadline
  deadline=$(($(date +%s) + 30))
  while [ -f "$STATE_DIR/ramp.pid" ]; do
    pid="$(cat "$STATE_DIR/ramp.pid" 2>/dev/null || true)"
    [ -n "$pid" ] || break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "  (ramp did not finish within 30s)" >&2
      return 1
    fi
  done
  sleep 0.2 # let the EXIT trap remove ramp.pid
}

# --- probe: learn this machine's sunrise/sunset for the fixed clock ---------
reset_state
stub_seed 6500 100
NOON="$(date -d "2025-06-15 12:00:00" +%s)"
run_apply "$NOON" || true
OK="$(jq -r '.ok // false' "$STATE" 2>/dev/null || echo false)"
SUNRISE="$(jq -r '.sunrise // 0' "$STATE" 2>/dev/null || echo 0)"
SUNSET="$(jq -r '.sunset // 0' "$STATE" 2>/dev/null || echo 0)"
if [ "$OK" != "true" ] || ! [ "$SUNRISE" -gt 0 ] 2>/dev/null || ! [ "$SUNSET" -gt "$SUNRISE" ] 2>/dev/null; then
  echo "hypr-sunset-tests: PROBE FAILED (ok=$OK sunrise=$SUNRISE sunset=$SUNSET reason=$(jq -r '.reason // "?"' "$STATE" 2>/dev/null))" >&2
  exit 1
fi
NIGHT=$((SUNSET + 3600))
SET_START=$((SUNSET - 45 * 60)) # transitionMin default 45
echo "hypr-sunset-tests: probe ok (sunrise=$SUNRISE sunset=$SUNSET)"

# --- (a) idempotent day / night ticks push nothing --------------------------
echo "scenario a: idempotent ticks"
reset_state
stub_seed 6500 100
m="$(writes_total)"
run_apply "$NOON"
assert_eq "day tick at target: 0 writes" 0 "$(count_writes "$m")"
assert_eq "day tick: phase day" "day" "$(jq -r '.phase' "$STATE")"

reset_state
stub_seed 3400 90
m="$(writes_total)"
run_apply "$NIGHT"
assert_eq "night tick at target: 0 writes" 0 "$(count_writes "$m")"
assert_eq "night tick: phase night" "night" "$(jq -r '.phase' "$STATE")"

# --- (b) a full sunset window pushes and lands on night ----------------------
echo "scenario b: sunset transition window"
reset_state
stub_seed 6500 100
m="$(writes_total)"
now=$((SET_START - 60))
while [ "$now" -le $((SUNSET + 30)) ]; do
  run_apply "$now"
  now=$((now + 30))
done
w="$(count_writes "$m")"
ticks=$(((SUNSET + 30 - (SET_START - 60)) / 30 + 1))
assert_ge "window: pushes occur" 1 "$w"
assert_le "window: fewer pushes than 2x ticks (skip rule holds)" $((ticks * 2)) "$w"
assert_eq "window: ends at night temperature" 3400 "$(cat "$STUB_STATE/temp")"

# --- (c) discrete ramp: many pushes, none byte-identical ---------------------
echo "scenario c: discrete ramp skips identical steps"
reset_state
set_settings '{"discreteRampSec":2,"rampStepMs":100}'
stub_seed 6500 100
m="$(writes_total)"
run_apply "$NIGHT" --ramp
wait_ramp
w="$(count_writes "$m")"
assert_ge "ramp: multiple pushes" 2 "$w"
assert_le "ramp: bounded pushes" 60 "$w"
dup="$(awk -v start="$m" 'NR>start && $1=="temperature" {if($2==last)d++; last=$2} END{print d+0}' "$STUB_WRITES")"
assert_eq "ramp: no byte-identical consecutive temperature pushes" 0 "$dup"
# Gamma spans only 90->100 across a whole sweep, so without the skip rule
# consecutive steps push the SAME gamma repeatedly. This is the assertion that
# actually bites if fade_between's `if [ "$g" != "$last_g" ]` guard is removed.
gdup="$(awk -v start="$m" 'NR>start && $1=="gamma" {if($2==last)d++; last=$2} END{print d+0}' "$STUB_WRITES")"
assert_eq "ramp: no byte-identical consecutive gamma pushes" 0 "$gdup"
assert_eq "ramp: ends at night temperature" 3400 "$(cat "$STUB_STATE/temp")"

# --- (d) preview fades out and back, writes no state.json --------------------
echo "scenario d: preview"
reset_state
stub_seed 6500 100
m="$(writes_total)"
run_apply "$NOON" --preview
if [ -f "$STATE_DIR/ramp.pid" ]; then pass "preview: RAMPFILE lock taken"; else fail "preview: no RAMPFILE lock"; fi
wait_ramp
assert_ge "preview: pushes occur (out and back)" 2 "$(count_writes "$m")"
assert_eq "preview: restores original temperature" 6500 "$(cat "$STUB_STATE/temp")"
assert_eq "preview: restores original gamma" 100 "$(cat "$STUB_STATE/gamma")"
if [ ! -f "$STATE" ]; then pass "preview: writes no state.json"; else fail "preview: wrote state.json"; fi

# --- (e) a tick landing mid-ramp is skipped ----------------------------------
# A real running ramp would keep pushing in the background while we count, so
# the "skipped" tick's writes could not be told apart from the ramp's. Instead
# stand in a live PID as the ramp lock: the tick must see ramp_active and skip
# without any concurrent pusher muddying the count.
echo "scenario e: tick skipped mid-ramp"
reset_state
stub_seed 6500 100
sleep 300 &
dummy=$!
echo "$dummy" >"$STATE_DIR/ramp.pid"
m="$(writes_total)"
run_apply "$NIGHT" # plain tick while a ramp owns the screen
assert_eq "mid-ramp tick: skipped (0 writes)" 0 "$(count_writes "$m")"
kill "$dummy" 2>/dev/null || true
wait "$dummy" 2>/dev/null || true
rm -f "$STATE_DIR/ramp.pid"

# --- (f) enabled==false disables; toggle round-trips -------------------------
echo "scenario f: disable / toggle"
reset_state
stub_seed 3400 90
echo '{"enabled":false,"disabledUntil":0}' >"$OVERRIDE"
run_apply "$NIGHT"
assert_eq "disabled tick: phase off (jq // does not swallow false)" "off" "$(jq -r '.phase' "$STATE")"

reset_state
stub_seed 6500 100
HYPR_SUNSET_NOW="$NOON" "$CTL" toggle >/dev/null 2>&1 || true
wait_ramp
assert_eq "ctl toggle: disables" "false" "$(jq -r 'if .enabled == false then "false" else "true" end' "$OVERRIDE")"
HYPR_SUNSET_NOW="$NOON" "$CTL" toggle >/dev/null 2>&1 || true
wait_ramp
assert_eq "ctl toggle: re-enables" "true" "$(jq -r 'if .enabled == false then "false" else "true" end' "$OVERRIDE")"

# --- (g) Layer 3: pushes.log records real writes, skips no-ops ---------------
echo "scenario g: pushes.log correlation record"
reset_state
stub_seed 6500 100
run_apply "$NIGHT" # night tick from a day stub -> real push
if [ -f "$STATE_DIR/pushes.log" ]; then pass "pushes.log: created on a real push"; else fail "pushes.log: missing after a real push"; fi
assert_eq "pushes.log: tags the tick kind" "tick" "$(awk 'END{print $4}' "$STATE_DIR/pushes.log" 2>/dev/null)"
assert_ge "pushes.log: has a line" 1 "$(wc -l <"$STATE_DIR/pushes.log" 2>/dev/null | tr -d ' ')"

reset_state
stub_seed 3400 90
run_apply "$NIGHT" # idempotent -> no push
if [ ! -f "$STATE_DIR/pushes.log" ]; then pass "pushes.log: an idempotent tick logs nothing"; else fail "pushes.log: written for a no-op tick"; fi

# --- informational: one tick's execve count (never asserted) -----------------
if command -v strace >/dev/null 2>&1; then
  reset_state
  stub_seed 6500 100
  n_execve="$(HYPR_SUNSET_NOW="$NOON" strace -f -qq -e trace=execve -c -o /dev/stdout \
    "$APPLY" 2>/dev/null | awk '/execve/{print $4}' | tail -n1)"
  echo "  (info) idle tick execve count: ${n_execve:-unknown}"
else
  echo "  (info) strace unavailable; skipping execve count (informational only)"
fi

# --- verdict -----------------------------------------------------------------
echo
if [ "$FAILS" -eq 0 ]; then
  echo "hypr-sunset-tests: ALL PASS"
  exit 0
else
  echo "hypr-sunset-tests: $FAILS FAILED"
  exit 1
fi

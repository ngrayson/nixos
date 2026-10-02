#!/usr/bin/env bash
# Script-level test suite for Hearth's Go3 battery alert
# (hosts/Hearth/go3-battery-alert/script.nix). It drives the REAL script against
# a scratch state dir through its env hooks — _READOUT stands in for the ssh
# check-in (set-but-empty = unreachable), _NOW fixes the clock, _DRY_RUN prints
# each message instead of posting it — so nothing here touches Go3, the tailnet
# or the Hearthchime webhook. Wired into `nix flake check` as the
# `hearth-go3-battery-alert-tests` check; also runs directly on a host.
#
# What it pins down is the once-per-episode promise: one low alert, one
# "charging again" follow-up, silence while unreachable or Unknown, and a
# silent rearm when a discharging readout climbs past the margin.
#
# Binary: `$HEARTH_GO3_BATTERY_ALERT_BIN` if set (the flake check), else
# `hearth-go3-battery-alert` from PATH.

set -uo pipefail
export LC_ALL=C

BIN="${HEARTH_GO3_BATTERY_ALERT_BIN:-hearth-go3-battery-alert}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "hearth-go3-battery-alert-tests: cannot find '$BIN'" >&2
  exit 1
}

S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
T0=1790000000
fails=0
OUT=""

# tick <readout> [now] — one timer tick; stdout lands in $OUT.
tick() {
  OUT="$(HEARTH_GO3_BATTERY_ALERT_STATE_DIR="$S" \
    HEARTH_GO3_BATTERY_ALERT_DRY_RUN=1 \
    HEARTH_GO3_BATTERY_ALERT_NOW="${2:-$T0}" \
    HEARTH_GO3_BATTERY_ALERT_READOUT="$1" \
    "$BIN" 2>/dev/null)"
  local rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: '$1' exited $rc"; fails=$((fails + 1)); }
}
reset() { rm -rf "$S"; mkdir -p "$S"; }
lines() { [ -z "$OUT" ] && echo 0 || printf '%s\n' "$OUT" | wc -l; }

check() { # check <name> <condition...>
  local name="$1"; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name (out: ${OUT:-<none>})"; fails=$((fails + 1)); fi
}
quiet() { [ "$(lines)" -eq 0 ]; }
says() { [ "$(lines)" -eq 1 ] && printf '%s' "$OUT" | grep -qF -- "$1"; }
low() { [ -e "$S/low" ]; }
armed() { [ ! -e "$S/low" ]; }

reset; tick "50 Not charging"
check "1 armed + plugged: silent, last-readout keeps 'Not charging'" \
  bash -c '[ "$(cat "$0/last-readout")" = "'"$T0"' 50 Not charging" ]' "$S"
check "1 ... and no message, still armed" bash -c "[ -z '$OUT' ] && [ ! -e '$S/low' ]"

reset; tick "24 Discharging"
check "2 armed + discharging < 25: low alert" says "24% and discharging below 25%"
check "2 ... latch records pct and since" \
  bash -c "grep -qx 'pct=24' '$S/low' && grep -qx 'since=$T0' '$S/low'"

tick "20 Discharging"
check "3 low + still discharging: silent" quiet
check "3 ... latch kept" low

cp "$S/last-readout" "$S/before"
tick ""
check "4 low + unreachable: silent" quiet
check "4 ... latch kept, last-readout untouched" \
  bash -c "[ -e '$S/low' ] && cmp -s '$S/before' '$S/last-readout'"

tick "20 Unknown"
check "5 low + Unknown: silent, latch kept" bash -c "[ -z '$OUT' ] && [ -e '$S/low' ]"

tick "45 Charging" $((T0 + 4320))
check "6 low + Charging: one follow-up" says "charging again: 45%. Was 24% 1h 12m ago"
check "6 ... re-armed" armed

tick "45 Charging" $((T0 + 4920))
check "7 second plugged tick: silent (once and only once)" quiet

reset; tick "24 Discharging"; a="$OUT"
tick "31 Discharging"; b="$OUT"; low && rearm=no || rearm=yes
tick "24 Discharging"
check "8 low -> discharging >= 30 rearms silently -> alerts again" \
  bash -c "[ -n '$a' ] && [ -z '$b' ] && [ '$rearm' = yes ] && [ -n '$OUT' ]"

reset; tick "24 Discharging"; tick "50 Not charging" $((T0 + 600))
check "9 low + Not charging: 'plugged in again' with status verbatim" \
  says "plugged in again: 50% (Not charging). Was 24% 10m ago"

reset; tick "20 Charging"
check "10 armed + Charging below threshold: silent" bash -c "[ -z '$OUT' ] && [ ! -e '$S/low' ]"

reset; printf 'pct=22\n' >"$S/low"; tick "40 Full"
check "11 hand-made latch without since: posts with 'earlier'" says "plugged in again: 40% (Full). Was 22% earlier"
check "11 ... re-armed" armed

if [ "$fails" -ne 0 ]; then
  echo "hearth-go3-battery-alert-tests: $fails failure(s)" >&2
  exit 1
fi
echo "hearth-go3-battery-alert-tests: all passed"

#!/usr/bin/env bash
# Script-level test for the Conveyor VM bar poller's card start/finish
# notifications (home/services/conveyor-vm-status.nix). It drives the REAL
# qs-conveyor-vm-status through its env hooks — CONVEYOR_K3 is a stub CLI,
# QS_CVM_OUT a scratch state file, QS_CVM_NOTIFY a stub that logs instead of
# notifying — so nothing here touches the VM or the desktop.
#
# What it pins down: one notification per pod start and finish, none while the
# pod set is unchanged, and none after a failed fetch (no baseline, no burst).
#
# Binary: `$QS_CONVEYOR_VM_STATUS_BIN` if set, else qs-conveyor-vm-status from PATH.
# Against an unswitched build:
#   P=$(nix build --no-link --print-out-paths '.#nixosConfigurations.Tawa.config.home-manager.users.wiz.home.path')
#   QS_CONVEYOR_VM_STATUS_BIN="$P/bin/qs-conveyor-vm-status" bash tests/conveyor-vm-status/run.sh

set -uo pipefail
export LC_ALL=C

BIN="${QS_CONVEYOR_VM_STATUS_BIN:-qs-conveyor-vm-status}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "conveyor-vm-status-tests: cannot find '$BIN'" >&2
  exit 1
}

S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
fails=0

cat >"$S/conveyor-k3" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "vm list") echo '{"host":{},"instances":[{"instance":"tesseract","status":"Running","enrolled":true,"linkVerified":true}]}' ;;
  "vm status") echo '{"status":"Running"}' ;;
  "vm pods") [ -e "$S/pods.fail" ] && exit 1; cat "$S/pods.json" ;;
esac
EOF
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/notify.log"\n' "$S" >"$S/notify"
chmod +x "$S/conveyor-k3" "$S/notify"
touch "$S/notify.log"

# poll <pods json> — one poller run with the pods cache forced stale.
poll() {
  printf '%s' "$1" >"$S/pods.json"
  if [ -f "$S/state.json" ]; then
    jq 'if .instances[0].pods then .instances[0].pods.checkedAt = 0 else . end' "$S/state.json" >"$S/state.tmp" && mv "$S/state.tmp" "$S/state.json"
  fi
  CONVEYOR_K3="$S/conveyor-k3" QS_CVM_OUT="$S/state.json" QS_CVM_NOTIFY="$S/notify" "$BIN" ||
    { echo "FAIL: poller exited $?"; fails=$((fails + 1)); }
}
check() { # check <name> <condition...>
  local name="$1"; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name (log: $(tr '\n' '|' <"$S/notify.log"))"; fails=$((fails + 1)); fi
}
count() { [ "$(wc -l <"$S/notify.log")" -eq "$1" ]; }
last() { tail -n1 "$S/notify.log" | grep -qF -- "$1"; }
running() { [ "$(jq -c '.instances[0].pods.running' "$S/state.json")" = "$1" ]; }

EMPTY='{"pods":[]}'
A='{"pods":[{"uid":"a","phase":"Running","assignment":{"projectName":"Stellarium","taskTitle":"Example card"}}]}'
B='{"pods":[{"uid":"b","phase":"Pending","assignment":null}]}'

poll "$EMPTY"
check "1 first fetch, no pods: silent" count 0
poll "$A"
check "2 pod appears: one 'started'" count 1
check "2 ... names project and card" last "tesseract started a card Stellarium: Example card"
check "2 ... bar count is 1" running 1
poll "$A"
check "3 same pod again: silent" count 1
poll "$EMPTY"
check "4 pod gone: one 'finished'" count 2
check "4 ... names the card" last "tesseract finished a card Stellarium: Example card"
check "4 ... bar count is 0" running 0
touch "$S/pods.fail"
poll "$EMPTY"
check "5 failed fetch: silent" count 2
check "5 ... pods is null" running null
rm "$S/pods.fail"
poll "$B"
check "6 first fetch after a failure: no baseline, silent" count 2
poll "$B"
check "7 same pod again: silent" count 2
poll "$EMPTY"
check "8 unassigned pod gone: 'finished' with fallback body" count 3
check "8 ... says (unassigned pod)" last "(unassigned pod)"

if [ "$fails" -ne 0 ]; then
  echo "conveyor-vm-status-tests: $fails failure(s)" >&2
  exit 1
fi
echo "conveyor-vm-status-tests: all passed"

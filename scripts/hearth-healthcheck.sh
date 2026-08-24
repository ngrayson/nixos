#!/usr/bin/env bash
# Post-activate probes for Hearth. Exit 0 only when every check passes.
# Intended: ssh hearth sudo bash -s < scripts/hearth-healthcheck.sh
set -euo pipefail

COLD_UUID="22C21140C2111A1D"
JELLYFIN_HEALTH="http://127.0.0.1:8096/health"
failed=0

ok() { printf '[ok]   %s\n' "$*"; }
fail() { printf '[fail] %s\n' "$*" >&2; failed=1; }

require_unit() {
  local unit="$1"
  if systemctl is-active --quiet "$unit"; then
    ok "$unit is active"
  else
    fail "$unit is not active ($(systemctl is-active "$unit" 2>/dev/null || true))"
  fi
}

require_unit sshd
require_unit tailscaled
require_unit jellyfin

if command -v tailscale >/dev/null 2>&1; then
  ts_json="$(tailscale status --json 2>/dev/null || true)"
  ts_ok=0
  if command -v python3 >/dev/null 2>&1 && [[ -n "$ts_json" ]]; then
    if printf '%s' "$ts_json" | python3 -c 'import json,sys
d=json.load(sys.stdin)
sys.exit(0 if d.get("BackendState")=="Running" and d.get("Self",{}).get("Online") else 1)' 2>/dev/null; then
      ts_ok=1
    fi
  elif printf '%s' "$ts_json" | grep -q '"BackendState":[[:space:]]*"Running"'; then
    ts_ok=1
  fi
  if ((ts_ok)); then
    ok "tailscale node is online"
  else
    fail "tailscale node is not online"
    tailscale status >&2 || true
  fi
else
  fail "tailscale is not on PATH"
fi

if findmnt /mnt/cold >/dev/null 2>&1; then
  src="$(findmnt -n -o SOURCE /mnt/cold 2>/dev/null || true)"
  uuid="$(findmnt -n -o UUID /mnt/cold 2>/dev/null || true)"
  if [[ "$uuid" == "$COLD_UUID" ]] || [[ "$src" == *"$COLD_UUID"* ]]; then
    ok "/mnt/cold is mounted (UUID $COLD_UUID)"
  else
    fail "/mnt/cold is mounted but UUID is '${uuid:-unknown}' (want $COLD_UUID)"
  fi
else
  fail "/mnt/cold is not mounted"
fi

if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 5 "$JELLYFIN_HEALTH" >/dev/null; then
    ok "Jellyfin health $JELLYFIN_HEALTH"
  else
    fail "Jellyfin health URL failed ($JELLYFIN_HEALTH)"
  fi
else
  fail "curl is not on PATH"
fi

if ((failed)); then
  printf 'Hearth health check failed\n' >&2
  exit 1
fi
printf 'Hearth health check passed\n'
exit 0

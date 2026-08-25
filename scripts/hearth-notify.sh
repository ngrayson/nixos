#!/usr/bin/env bash
# Shared notify helper. v1 posts Discord only for event id health-fail.
# Fail-open: missing file or curl error exits 0. Never print the webhook.
set -euo pipefail

event="${1:-}"
if [[ "$event" != "health-fail" ]]; then
  exit 0
fi

webhook_file="${HEARTH_NOTIFY_WEBHOOK_FILE:-/run/secrets/hearth-discord-webhook}"
if [[ ! -r "$webhook_file" ]]; then
  printf '\033[1;33m[warn]\033[0m hearth-notify: webhook file missing; skip Discord (%s).\n' "$event" >&2
  exit 0
fi

url="$(tr -d '\n' <"$webhook_file")"
if [[ -z "$url" ]]; then
  printf '\033[1;33m[warn]\033[0m hearth-notify: webhook file empty; skip Discord.\n' >&2
  exit 0
fi

branch="${HEARTH_NOTIFY_BRANCH:-unknown}"
lane="${HEARTH_NOTIFY_LANE:-unknown}"
generation="${HEARTH_NOTIFY_GENERATION:-unknown}"
log_path="${HEARTH_NOTIFY_LOG:-}"

content="Hearth switch activated but health check failed."
content+=" Branch ${branch} (${lane})."
content+=" Generation ${generation}."
if [[ -n "$log_path" ]]; then
  content+=" Log ${log_path}."
fi

payload="$(printf '%s' "$content" | python3 -c 'import json,sys; print(json.dumps({"content": sys.stdin.read()}))')"

if ! curl -fsS -o /dev/null --max-time 10 \
  -H 'Content-Type: application/json' \
  -d "$payload" \
  "$url"; then
  printf '\033[1;33m[warn]\033[0m hearth-notify: Discord post failed; deploy exit code unchanged.\n' >&2
fi
exit 0

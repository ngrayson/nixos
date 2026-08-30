#!/usr/bin/env bash
# Post-activate probes for Hearth. Exit 0 only when every check passes.
# Intended: ssh hearth sudo bash -s < scripts/hearth-healthcheck.sh
set -euo pipefail

COLD_UUID="${HEARTH_COLD_UUID:-22C21140C2111A1D}"
JELLYFIN_HEALTH="${HEARTH_JELLYFIN_HEALTH_URL:-http://127.0.0.1:8096/health}"
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
  if [[ -z "$ts_json" ]]; then
    fail "tailscale status --json produced no output"
    tailscale status >&2 || true
  elif command -v python3 >/dev/null 2>&1; then
    if printf '%s' "$ts_json" | python3 -c 'import json,sys
d=json.load(sys.stdin)
sys.exit(0 if d.get("BackendState")=="Running" and d.get("Self",{}).get("Online") else 1)' 2>/dev/null; then
      ts_ok=1
    fi
  else
    # Hearth often has no python3 on sudo PATH.
    online="$(printf '%s' "$ts_json" | awk '
      /"Self"/ { inself = 1 }
      inself && /"Online"/ {
        if ($0 ~ /true/) { print "true"; exit }
        if ($0 ~ /false/) { print "false"; exit }
      }
    ')"
    backend="$(printf '%s' "$ts_json" | awk -F'"' '/"BackendState"/ { print $4; exit }')"
    if [[ "$online" == "true" && "$backend" == "Running" ]]; then
      ts_ok=1
    fi
  fi
  if ((ts_ok)); then
    ok "tailscale BackendState=Running and Self.Online"
  elif [[ -n "$ts_json" ]]; then
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

# Library paths are Jellyfin server state, not jellyfin.nix. COLD is mounted
# case-sensitively and Jellyfin does not trim mblink files, so a wrong capital
# and a trailing newline both scan as "inaccessible or empty, skipping" with the
# tracks sitting unread. Fail the deploy instead of leaving a silent empty shelf.
JELLYFIN_ROOT="${HEARTH_JELLYFIN_ROOT:-/var/lib/jellyfin/root/default}"
if [[ ! -d "$JELLYFIN_ROOT" ]]; then
  # Skipping quietly here would restore the green-but-empty deploy this whole
  # block exists to catch, so a moved or mistyped root is itself a failure.
  fail "Jellyfin library root $JELLYFIN_ROOT does not exist"
else
  links="$(find "$JELLYFIN_ROOT" -name '*.mblink' -type f 2>/dev/null | sort || true)"
  if [[ -z "$links" ]]; then
    fail "no Jellyfin library folders under $JELLYFIN_ROOT"
  else
    libdirs="$(while IFS= read -r link; do
      [[ -n "$link" ]] && dirname "$link"
    done <<<"$links" | sort -u)"
    while IFS= read -r libdir; do
      [[ -n "$libdir" ]] || continue
      lib="$(basename "$libdir")"
      linked=()
      for link in "$libdir"/*.mblink; do
        [[ -f "$link" ]] || continue
        path="$(cat "$link")"
        linked+=("$path")
        # cat strips trailing newlines and Jellyfin does not, so the byte counts
        # diverge exactly when the file carries one. Do not probe for the newline
        # with a command substitution; that strips it too and always looks clean.
        if (($(wc -c <"$link") != $(printf '%s' "$path" | wc -c))); then
          fail "Jellyfin '$lib' mblink ends in a newline; write it with printf, not echo"
        elif [[ ! -d "$path" ]]; then
          fail "Jellyfin '$lib' points at missing '$path' (COLD is case-sensitive)"
        else
          ok "Jellyfin '$lib': $path"
        fi
      done

      opts="$libdir/options.xml"
      ((${#linked[@]})) || continue
      [[ -f "$opts" ]] || continue
      # Checking only that each mblink appears in options.xml lets a stale entry
      # from a renamed folder survive, and Jellyfin keeps scanning it. Compare
      # the two sets both ways. &amp; is unescaped because a path may hold '&'.
      declared="$(grep -o '<Path>[^<]*</Path>' "$opts" |
        sed -e 's|<Path>||' -e 's|</Path>||' -e 's|&amp;|\&|g' | sort -u || true)"
      have="$(printf '%s\n' "${linked[@]}" | sort -u)"
      while IFS= read -r stale; do
        [[ -n "$stale" ]] || continue
        fail "Jellyfin '$lib' options.xml declares '$stale' with no mblink (stale after a rename)"
      done < <(comm -13 <(printf '%s\n' "$have") <(printf '%s\n' "$declared"))
      while IFS= read -r undeclared; do
        [[ -n "$undeclared" ]] || continue
        fail "Jellyfin '$lib' options.xml does not declare mblink path '$undeclared'"
      done < <(comm -23 <(printf '%s\n' "$have") <(printf '%s\n' "$declared"))
    done <<<"$libdirs"
  fi
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

require_unit caddy
if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 5 --resolve home.wizt.org:443:100.84.222.78 \
    https://home.wizt.org/status.json | grep -q '"root"'; then
    ok "home.wizt.org/status.json has root"
  else
    fail "home.wizt.org/status.json missing or has no root (Caddy is on 100.84.222.78)"
  fi
fi

if ((failed)); then
  printf 'Hearth health check failed\n' >&2
  exit 1
fi
printf 'Hearth health check passed\n'
exit 0

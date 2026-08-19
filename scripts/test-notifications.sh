#!/usr/bin/env bash
# Fire desktop notifications that exercise dunst / FreeDesktop Notification aspects.
# Stack: dunst as a systemd user unit (`home/services/dunst.nix`), themed from `config.theme.hex`.
# If styling looks stale, check `systemctl --user status dunst` — a daemon started outside systemd
# holds org.freedesktop.Notifications and keeps serving whatever dunstrc it read at startup.
#
# Usage:
#   ./scripts/test-notifications.sh              # full suite (paced)
#   ./scripts/test-notifications.sh --quick      # shorter delays
#   ./scripts/test-notifications.sh --list       # print cases without sending
#   ./scripts/test-notifications.sh urgency markup actions progress stack
#   ./scripts/test-notifications.sh --delay 2.5 urgency icons
set -euo pipefail

DELAY=1.8
QUICK=0
LIST_ONLY=0
CASES=()

info()  { printf '\033[1;34m[info]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m   %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [case...]

Send test notifications covering urgency, icons, markup, length, progress,
actions, replace/stack, categories, timeouts, and burst behavior.

Options:
  --quick         Use a shorter pause between cases (0.6s)
  --delay SECONDS Pause between cases (default: ${DELAY})
  --list          Print case names and descriptions; do not send
  -h, --help      Show this help

Cases (default: all):
  urgency     low / normal / critical
  icons       named icons + missing icon fallback
  markup      bold/italic/underline/hyperlink body
  length      long title, long body, multiline, emoji
  progress    value hint 0→100 (progress bar if enabled)
  actions     action buttons (blocks until closed / clicked)
  replace     replace-id updates in place
  stack       x-dunst-stack-tag / --stack-tag
  category    FreeDesktop categories
  timeout     short / long / never expire
  transient   -e transient vs history-eligible
  appname     distinct -a application names
  burst       several at once (stacking / gaps)
  caps        print server capabilities (no toast)

Requires: notify-send (libnotify). Prefer dunstify when present for stack-tag /
raw-icon / --capabilities.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    --delay)
      [[ $# -ge 2 ]] || { error "--delay needs a value"; exit 2; }
      DELAY="$2"
      shift 2
      ;;
    --list) LIST_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)
      error "Unknown option: $1"
      usage >&2
      exit 2
      ;;
    *)
      CASES+=("$1")
      shift
      ;;
  esac
done

if (( QUICK )); then
  DELAY=0.6
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    error "Missing required command: $1"
    exit 2
  }
}

require_cmd notify-send

HAVE_DUNSTIFY=0
if command -v dunstify >/dev/null 2>&1; then
  HAVE_DUNSTIFY=1
fi

# Prefer a few well-known freedesktop icon names; fall back silently if absent.
ICON_INFO="${TEST_NOTIF_ICON_INFO:-dialog-information}"
ICON_WARN="${TEST_NOTIF_ICON_WARN:-dialog-warning}"
ICON_ERR="${TEST_NOTIF_ICON_ERR:-dialog-error}"
ICON_APP="${TEST_NOTIF_ICON_APP:-utilities-terminal}"
ICON_MAIL="${TEST_NOTIF_ICON_MAIL:-mail-unread}"
ICON_UPDATE="${TEST_NOTIF_ICON_UPDATE:-software-update-available}"

pause() {
  (( LIST_ONLY )) && return 0
  sleep "$DELAY"
}

announce() {
  local name="$1" desc="$2"
  if (( LIST_ONLY )); then
    printf '  %-10s  %s\n' "$name" "$desc"
    return 0
  fi
  info "${name}: ${desc}"
}

send() {
  (( LIST_ONLY )) && return 0
  # shellcheck disable=SC2068
  notify-send "$@"
}

send_dunst() {
  (( LIST_ONLY )) && return 0
  if (( ! HAVE_DUNSTIFY )); then
    warn "dunstify not on PATH; skipping dunst-specific send"
    return 0
  fi
  # shellcheck disable=SC2068
  dunstify "$@"
}

case_wanted() {
  local name="$1"
  (( ${#CASES[@]} == 0 )) && return 0
  local c
  for c in "${CASES[@]}"; do
    [[ "$c" == "$name" ]] && return 0
  done
  return 1
}

run_caps() {
  announce "caps" "server capabilities / info"
  (( LIST_ONLY )) && return 0
  if (( HAVE_DUNSTIFY )); then
    echo "--- capabilities ---"
    dunstify --capabilities || true
    echo "--- serverinfo ---"
    dunstify --serverinfo || true
  else
    warn "Install dunstify (dunst package) for --capabilities"
  fi
  if command -v dunstctl >/dev/null 2>&1; then
    echo "--- dunstctl ---"
    dunstctl is-paused 2>/dev/null | sed 's/^/paused: /' || true
    dunstctl count 2>/dev/null || true
  fi
}

run_urgency() {
  announce "urgency" "low / normal / critical (frame + timeout defaults)"
  send -u low -a "Test · Urgency" -i "$ICON_INFO" \
    "Low urgency" "Should be the quietest / least sticky style."
  pause
  send -u normal -a "Test · Urgency" -i "$ICON_WARN" \
    "Normal urgency" "Default importance — most app toasts land here."
  pause
  send -u critical -a "Test · Urgency" -i "$ICON_ERR" \
    "Critical urgency" "Should stand out (color, timeout, or both)."
  pause
}

run_icons() {
  announce "icons" "named icons, app-icon, and missing-icon fallback"
  send -a "Test · Icons" -i "$ICON_INFO" \
    "Named icon" "dialog-information (or TEST_NOTIF_ICON_INFO)."
  pause
  send -a "Test · Icons" -i "$ICON_MAIL" \
    "Mail icon" "mail-unread — checks icon theme lookup."
  pause
  send -a "Test · Icons" -n "$ICON_APP" -i "$ICON_UPDATE" \
    "App icon + content icon" "Both -n/--app-icon and -i/--icon set."
  pause
  send -a "Test · Icons" -i "this-icon-does-not-exist-xyz" \
    "Missing icon" "Daemon should fall back without crashing."
  pause
  if (( HAVE_DUNSTIFY )); then
    local raw=""
    if command -v jq >/dev/null 2>&1 && [[ -f "${HOME}/.config/quickshell/theme.json" ]]; then
      raw="$(jq -r '.wallpaper // empty' "${HOME}/.config/quickshell/theme.json" 2>/dev/null || true)"
    fi
    if [[ -z "$raw" || ! -f "$raw" ]]; then
      for cand in \
        "${HOME}/.config/nixos/login-bg.png" \
        "${HOME}/.config/nixos/izar-utopia.png" \
        "${HOME}/.face"; do
        if [[ -f "$cand" ]]; then
          raw="$cand"
          break
        fi
      done
    fi
    if [[ -n "$raw" && -f "$raw" ]]; then
      send_dunst -a "Test · Icons" -I "$raw" \
        "Raw image icon" "dunstify -I (image data over the wire)."
      pause
    else
      warn "No image found for raw-icon case; skipped"
    fi
  fi
}

run_markup() {
  announce "markup" "Pango-ish body: bold, italic, underline, hyperlink"
  # dunst may or may not advertise body-markup; still worth probing.
  send -a "Test · Markup" -i "$ICON_INFO" \
    "Markup probe" \
    "<b>bold</b> · <i>italic</i> · <u>underline</u> · <a href=\"https://example.com\">link</a>"
  pause
  send -a "Test · Markup" -i "$ICON_INFO" \
    "Escaped entities" \
    "Ampersand &amp; · &lt;angle&gt; · &quot;quotes&quot;"
  pause
}

run_length() {
  announce "length" "wrapping, multiline, emoji, empty-ish bodies"
  send -a "Test · Length" -i "$ICON_INFO" \
    "Short" "One line."
  pause
  send -a "Test · Length" -i "$ICON_INFO" \
    "A rather long title that should wrap or ellipsize depending on width settings" \
    "Body is normal length."
  pause
  send -a "Test · Length" -i "$ICON_INFO" \
    "Long body" \
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."
  pause
  send -a "Test · Length" -i "$ICON_INFO" \
    "Multiline body" \
    $'Line one\nLine two\nLine three — check gap / line-height.'
  pause
  send -a "Test · Length" -i "$ICON_INFO" \
    "Emoji · 🔔 ✨ 🚀" \
    "Glyphs: ✅ ❌ ⚠️ 🔋 📩 — font / fallback rendering."
  pause
  send -a "Test · Length" -i "$ICON_INFO" \
    "Title only"
  pause
}

run_progress() {
  announce "progress" "int:value hint (dunst progress bar when enabled)"
  local v
  for v in 0 25 50 75 100; do
    send -a "Test · Progress" -i "$ICON_UPDATE" \
      -h "int:value:${v}" \
      -h "string:x-dunst-stack-tag:qs-test-progress" \
      "Progress ${v}%" "value=${v} — should update the same stacked toast."
    # Faster than DELAY so the bar animates as a sequence
    (( LIST_ONLY )) || sleep 0.35
  done
  pause
}

run_actions() {
  announce "actions" "action buttons (waits for click/dismiss — interact or Esc)"
  (( LIST_ONLY )) && return 0
  info "Waiting on action notification (click a button or dismiss)…"
  # -w/--wait blocks until closed; action name printed to stdout
  local result
  result="$(notify-send -w -a "Test · Actions" -i "$ICON_INFO" \
    -A "open=Open" -A "snooze=Snooze" -A "dismiss=Dismiss" \
    "Action buttons" "Pick Open / Snooze / Dismiss, or close the toast." || true)"
  ok "action result: ${result:-<closed without action>}"
  pause
}

run_replace() {
  announce "replace" "replace-id updates one notification in place"
  (( LIST_ONLY )) && return 0
  local id
  id="$(notify-send -p -a "Test · Replace" -i "$ICON_INFO" \
    "Replace step 1/3" "This toast will be rewritten twice.")"
  ok "id=${id}"
  sleep 0.7
  notify-send -r "$id" -a "Test · Replace" -i "$ICON_WARN" \
    "Replace step 2/3" "Same id — should not spawn a second bubble."
  sleep 0.7
  notify-send -r "$id" -a "Test · Replace" -i "$ICON_ERR" \
    "Replace step 3/3" "Final body for this replace sequence."
  pause
}

run_stack() {
  announce "stack" "x-dunst-stack-tag / dunstify --stack-tag"
  send -a "Test · Stack" -i "$ICON_INFO" \
    -h "string:x-dunst-stack-tag:qs-test-stack" \
    "Stack tag A" "First — next with same tag should replace."
  pause
  send -a "Test · Stack" -i "$ICON_WARN" \
    -h "string:x-dunst-stack-tag:qs-test-stack" \
    "Stack tag B" "Replaced A via x-dunst-stack-tag."
  pause
  if (( HAVE_DUNSTIFY )); then
    send_dunst -a "Test · Stack" -i "$ICON_INFO" --stack-tag "qs-test-stack-cli" \
      "Stack CLI A" "dunstify --stack-tag first."
    pause
    send_dunst -a "Test · Stack" -i "$ICON_UPDATE" --stack-tag "qs-test-stack-cli" \
      "Stack CLI B" "Replaced via --stack-tag."
    pause
  fi
}

run_category() {
  announce "category" "FreeDesktop notification categories"
  send -a "Test · Category" -i "$ICON_MAIL" -c "email.arrived" \
    "email.arrived" "Category hint for mail-style rules."
  pause
  send -a "Test · Category" -i "$ICON_ERR" -c "device.error" \
    "device.error" "Category hint for error-style rules."
  pause
  send -a "Test · Category" -i "$ICON_UPDATE" -c "im" \
    "im" "Instant-message category."
  pause
}

run_timeout() {
  announce "timeout" "expire-time short / long / sticky (0)"
  send -a "Test · Timeout" -i "$ICON_INFO" -t 1000 \
    "1s timeout" "Should vanish quickly."
  pause
  send -a "Test · Timeout" -i "$ICON_INFO" -t 8000 \
    "8s timeout" "Stays longer than the suite delay."
  pause
  send -u critical -a "Test · Timeout" -i "$ICON_ERR" -t 0 \
    "Sticky (timeout 0)" "Dismiss manually — tests never-expire path."
  pause
}

run_transient() {
  announce "transient" "transient (-e) vs normal history behavior"
  send -e -a "Test · Transient" -i "$ICON_INFO" \
    "Transient" "Marked -e; often skipped in history."
  pause
  send -a "Test · Transient" -i "$ICON_INFO" \
    "Not transient" "Eligible for history / recall if enabled."
  pause
}

run_appname() {
  announce "appname" "distinct -a names (rules / icon / grouping)"
  send -a "Spotify" -i "spotify" \
    "Fake Spotify" "App name only — for per-app dunst rules later."
  pause
  send -a "Firefox" -i "firefox" \
    "Fake Firefox" "Another app name for rule matching."
  pause
  send -a "NixOS rebuild" -i "$ICON_UPDATE" \
    "Fake rebuild OK" "Mirrors os-rebuild success toast style."
  pause
}

run_burst() {
  announce "burst" "rapid-fire stack to inspect gaps / max displayed"
  (( LIST_ONLY )) && return 0
  local i
  for i in 1 2 3 4 5; do
    notify-send -a "Test · Burst" -i "$ICON_INFO" \
      "Burst ${i}/5" "Simultaneous stacking / notification_limit."
  done
  pause
}

ALL_CASES=(
  caps
  urgency
  icons
  markup
  length
  progress
  actions
  replace
  stack
  category
  timeout
  transient
  appname
  burst
)

if (( LIST_ONLY )); then
  info "Available cases:"
fi

if (( ! LIST_ONLY )); then
  info "dunstify: $( (( HAVE_DUNSTIFY )) && echo yes || echo no )"
  info "delay: ${DELAY}s"
  if command -v dunstctl >/dev/null 2>&1 && dunstctl is-paused >/dev/null 2>&1; then
    ok "dunstctl reachable"
  elif pgrep -a dunst >/dev/null 2>&1; then
    ok "dunst process found"
  else
    warn "dunst does not appear to be running — another notification daemon may own the bus"
  fi
fi

for name in "${ALL_CASES[@]}"; do
  case_wanted "$name" || continue
  "run_${name}"
done

if (( LIST_ONLY )); then
  exit 0
fi

ok "Suite finished. Dismiss any sticky/critical leftovers manually."
info "Tip: dunstctl history / dunstctl close-all  (if dunstctl is available)"

#!/usr/bin/env bash
# Fast path for home.wizt.org: build only the dashboard and rsync it to Hearth.
#
# scripts/hearth-deploy.sh evaluates, builds, copies and activates the entire
# Hearth system for any change at all, so a one-line CSS tweak costs the same
# as a kernel bump. Caddy now serves the dashboard off
# /var/lib/hearth-intranet/current instead of a Nix store path, so replacing
# that directory's contents is the whole deploy FOR THE DASHBOARD: no closure
# copy, no activation, and no Caddy restart — file_server reads the directory
# per request. The kiosk picks the change up on its own via build-id.txt.
#
# It is NOT the whole deploy for anything a Hearth systemd unit bakes at eval
# time. Those ship only with `hearth-deploy switch`: transit.busStops,
# obaApiKey and obaPollSeconds (hosts/Hearth/intranet-transit.nix), weather for
# AQI (intranet-aqi.nix), calendar (intranet-calendar.nix) and
# gallery.galleryDir (intranet-gallery.nix, caddy.nix). The stop list is the
# one that bites: this script ships a new intranet-config.js and build-id, the
# kiosk reloads, and the page keeps showing the poller's old stops. So before
# the push prompt it diffs the checkout's busStops against the live
# /transit.json and warns when they differ.
#
# This deploys the WORKING CHECKOUT, not origin/deploy/hearth. That is the
# point (iterate without committing), but it means the served dashboard can
# diverge from the pin until the next real `hearth-deploy switch`, which
# re-syncs the declared build over the top via hearth-intranet-sync.service.
set -euo pipefail

info() { printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[err]\033[0m  %s\n" "$*" >&2; }
ok() { printf "\033[1;32m[ok]\033[0m   %s\n" "$*"; }

# Same SSH conventions as hearth-deploy.sh: the `hearth` alias from
# home/programs/ssh-hearth.nix, not raw MagicDNS (different host key).
TARGET="${HEARTH_SSH_TARGET:-hearth}"
SERVE_DIR="/var/lib/hearth-intranet/current"
TAILNET_IPV4="100.84.222.78"

usage() {
  cat <<'USAGE'
Usage: hearth-intranet-deploy [--yes]

Builds .#hearth-intranet from this checkout and rsyncs it into
/var/lib/hearth-intranet/current on Hearth. No nixos-rebuild, no Caddy
restart. A later `hearth-deploy switch` restores whatever the repo declares.
Settings baked into Hearth systemd units (bus stops, OBA key/interval, AQI,
calendar, gallery dir) do not ship this way; they need `hearth-deploy switch`.

  --yes   skip the confirmation prompt
USAGE
}

refuse_if_on_hearth() {
  if [[ "$(hostname)" == "Hearth" ]]; then
    error "This is Hearth. Build and deploy from Tawa with hearth-intranet-deploy."
    return 1
  fi
}

# Fetch one file from the served dashboard over the tailnet. --resolve pins the
# vhost to Hearth's tailnet address so the check works without MagicDNS.
served_get() {
  curl -fsS --max-time 5 --resolve "home.wizt.org:443:${TAILNET_IPV4}" \
    "https://home.wizt.org/$1"
}

# The stop list is baked into hearth-intranet-transit.service, so this fast
# path cannot change it. Compare the posted stop ids the checkout would poll
# with the ids the live poller is actually polling and warn on a difference.
# Non-fatal like the build-id probe: a mismatch must not block a CSS push, and
# a tailnet outage says nothing about the stops.
#
# Only `id`s are compared. A name-only edit is also unit-baked and also needs a
# switch, but transit.json falls back to OBA's name when the config name is
# empty, so names cannot be diffed without false alarms; obaApiKey and
# obaPollSeconds are not in intranet-config.js at all.
warn_if_stops_diverge() {
  local out="$1"
  if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    warn "jq/curl not on PATH; cannot compare the checkout's busStops with the live poller."
    return 0
  fi
  [[ -f "$out/intranet-config.js" ]] || {
    warn "No intranet-config.js in the build; cannot compare busStops with the live poller."
    return 0
  }

  # Mirror skip_stop() in hosts/Hearth/intranet-transit.nix: transit.json only
  # lists stops the poller queried, so a kept-but-skipped Houston entry must
  # not count on this side either.
  local checkout_ids live_ids
  checkout_ids="$(sed 's/^window\.hearthIntranet = //; s/;[[:space:]]*$//' "$out/intranet-config.js" \
    | jq -r '.transit.busStops // []
      | map(if type == "string" then {id: .} else . end)
      | map(select((.skip // false) | not))
      | map(select(((.feed // "") | ascii_downcase) as $f | $f != "houston" and $f != "metro"))
      | map((.id // .stopId // "") | tostring)
      | map(select(. != "" and . != "25027" and . != "25028"))
      | sort | .[]')" || {
    warn "Could not read transit.busStops from the built intranet-config.js; skipping the live comparison."
    return 0
  }
  live_ids="$(served_get transit.json 2>/dev/null | jq -r '[.stops[]?.id | tostring] | sort | .[]')" || {
    warn "Could not read https://home.wizt.org/transit.json; cannot confirm the live poller's stop list matches this checkout."
    return 0
  }

  local n m
  n="$(printf '%s\n' "$checkout_ids" | grep -c .)" || n=0
  m="$(printf '%s\n' "$live_ids" | grep -c .)" || m=0
  if [[ "$checkout_ids" == "$live_ids" ]]; then
    ok "busStops match the live poller (${n} stops)."
    return 0
  fi
  warn "busStops in hosts/Hearth/intranet/config/transit/config.nix differ from what Hearth's poller is running (checkout ${n}, live ${m})."
  warn "This fast path cannot ship them: the stop list is baked into hearth-intranet-transit.service."
  warn "Run: hearth-deploy build && hearth-deploy switch --yes"
  diff <(printf '%s\n' "$checkout_ids") <(printf '%s\n' "$live_ids") || true
}

# The build is --impure and reads these through builtins.getEnv NIXOS_DIR.
# Without them it silently falls back to the example locations and would ship
# a dashboard pointing at the wrong city.
require_local_intranet_config() {
  local base="$NIXOS_DIR/hosts/Hearth/intranet/config"
  local widget missing=0
  for widget in weather transit; do
    if [[ ! -f "$base/$widget/config.nix" ]]; then
      error "Missing $base/$widget/config.nix"
      error "Copy config.example.nix to config.nix and add local settings (gitignored)."
      missing=1
    fi
  done
  return "$missing"
}

main() {
  local no_prompt=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) no_prompt=1 ;;
      -h | --help)
        usage
        return 0
        ;;
      *)
        error "Unknown argument: $1"
        usage
        return 2
        ;;
    esac
    shift
  done

  NIXOS_DIR="${NIXOS_DIR:-$HOME/.config/nixos}"
  NIXOS_DIR="$(cd "$NIXOS_DIR" 2>/dev/null && pwd -P)" || {
    error "NixOS directory does not exist: ${NIXOS_DIR:-<unset>}"
    return 2
  }
  export NIXOS_DIR
  [[ -f "$NIXOS_DIR/flake.nix" ]] || {
    error "flake.nix not found under $NIXOS_DIR"
    return 2
  }
  command -v nix >/dev/null 2>&1 || {
    error "nix is not available"
    return 2
  }

  refuse_if_on_hearth || return 1
  require_local_intranet_config || return 1

  info "nix build ${NIXOS_DIR}#hearth-intranet --impure"
  local out
  # --no-link so this never clobbers ./result out from under an in-flight
  # nixos-rebuild in the same checkout.
  out="$(nix build "${NIXOS_DIR}#hearth-intranet" --impure --no-link --print-out-paths)" || {
    error "Build failed."
    return 1
  }
  [[ -d "$out" ]] || {
    error "Build produced no directory: ${out:-<empty>}"
    return 1
  }

  local build_id="unknown"
  if [[ -f "$out/build-id.txt" ]]; then
    build_id="$(cat "$out/build-id.txt")"
  fi
  ok "Built ${out}"
  info "build-id ${build_id:0:12}"
  warn_if_stops_diverge "$out"

  if (( ! no_prompt )) && [[ -t 0 ]]; then
    local reply
    read -r -p "Push to ${TARGET}:${SERVE_DIR}? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || {
      warn "Aborted."
      return 1
    }
  fi

  # sudo on the far side: the served directory is root-owned (tmpfiles), the
  # same passwordless sudo hearth-deploy already relies on for activation.
  # --chmod matches hearth-intranet-sync.service so the two deploy paths leave
  # identical permissions behind.
  #
  # --checksum is required, not defensive: Nix pins every store file's mtime to
  # 1, so rsync's default size+mtime quick check skips any file whose length did
  # not change. build-id.txt is always 65 bytes, and it is exactly the file the
  # kiosk polls to decide whether to reload — without --checksum a fast-path
  # deploy ships new assets under a stale build-id and no client ever reloads.
  info "rsync -> ${TARGET}:${SERVE_DIR}"
  ssh "$TARGET" sudo mkdir -p "$SERVE_DIR" || {
    error "Could not create ${SERVE_DIR} on ${TARGET}."
    return 1
  }
  rsync -a --checksum --delete --chmod=D755,F644 --rsync-path="sudo rsync" \
    "$out/" "${TARGET}:${SERVE_DIR}/" || {
    error "rsync failed."
    return 1
  }
  ok "Synced."

  # End-to-end confirmation that Caddy is actually serving the new content.
  # Non-fatal: the sync above is the deploy, and a curl that cannot reach the
  # tailnet says nothing about whether it worked.
  if command -v curl >/dev/null 2>&1; then
    local served
    served="$(served_get build-id.txt 2>/dev/null | tr -d '[:space:]')" || served=""
    if [[ -z "$served" ]]; then
      warn "Could not read https://home.wizt.org/build-id.txt (tailnet down?); sync itself succeeded."
    elif [[ "$served" == "$build_id" ]]; then
      ok "home.wizt.org is serving build-id ${served:0:12}. Kiosk reloads within 120s."
    else
      warn "home.wizt.org reports build-id ${served:0:12}, expected ${build_id:0:12}."
    fi
  fi

  warn "Hearth now serves this checkout, not origin/deploy/hearth."
  warn "The next hearth-deploy switch re-syncs whatever the repo declares."
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi

#!/usr/bin/env bash
# Fast path for home.wizt.org: build only the dashboard and rsync it to Hearth.
#
# scripts/hearth-deploy.sh evaluates, builds, copies and activates the entire
# Hearth system for any change at all, so a one-line CSS tweak costs the same
# as a kernel bump. Caddy now serves the dashboard off
# /var/lib/hearth-intranet/current instead of a Nix store path, so replacing
# that directory's contents is the whole deploy: no closure copy, no
# activation, and no Caddy restart — file_server reads the directory per
# request. The kiosk picks the change up on its own via build-id.txt.
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

  --yes   skip the confirmation prompt
USAGE
}

refuse_if_on_hearth() {
  if [[ "$(hostname)" == "Hearth" ]]; then
    error "This is Hearth. Build and deploy from Tawa with hearth-intranet-deploy."
    return 1
  fi
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
  info "rsync -> ${TARGET}:${SERVE_DIR}"
  ssh "$TARGET" sudo mkdir -p "$SERVE_DIR" || {
    error "Could not create ${SERVE_DIR} on ${TARGET}."
    return 1
  }
  rsync -a --delete --chmod=D755,F644 --rsync-path="sudo rsync" \
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
    served="$(curl -fsS --max-time 5 --resolve "home.wizt.org:443:${TAILNET_IPV4}" \
      https://home.wizt.org/build-id.txt 2>/dev/null | tr -d '[:space:]')" || served=""
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

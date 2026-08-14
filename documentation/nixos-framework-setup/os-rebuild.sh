#!/usr/bin/env bash
set -euo pipefail

# Guided flake-aware NixOS rebuild helper.
#
# Usage:
#   os-rebuild [build|dry-activate|test|switch|boot] [options]
#
# Options:
#   --host HOST   Flake host output (default: current hostname)
#   --edit        Open flake.nix before validation
#   --no-edit     Do not open an editor (default)
#   --yes         Skip the pre-rebuild confirmation
#   --commit      Offer to commit after a successful rebuild
#   -h, --help    Show this help
#
# Environment:
#   NIXOS_DIR              Flake directory (default: ~/.config/nixos)
#   NIXOS_HOST             Flake host output (default: hostname)
#   OS_REBUILD_LOG_DIR     Log directory (default: ~/.cache/os-rebuild)
#   OS_REBUILD_NO_PROMPT=1 Equivalent to --yes

info() { printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[err]\033[0m  %s\n" "$*" >&2; }
ok() { printf "\033[1;32m[ok]\033[0m   %s\n" "$*"; }

usage() {
  sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//'
}

prompt_confirm() {
  local reply
  printf "\n%s [Y/n]: " "$*"
  read -r reply || true
  case "${reply:-Y}" in
    Y | y | yes | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ACTION="switch"
NIXOS_DIR="${NIXOS_DIR:-$HOME/.config/nixos}"
NIXOS_HOST="${NIXOS_HOST:-$(hostname)}"
LOG_DIR="${OS_REBUILD_LOG_DIR:-$HOME/.cache/os-rebuild}"
NO_PROMPT="${OS_REBUILD_NO_PROMPT:-0}"
EDIT=0
COMMIT=0

while (($#)); do
  case "$1" in
    build | dry-activate | test | switch | boot)
      ACTION="$1"
      ;;
    --host)
      shift
      NIXOS_HOST="${1:-}"
      [[ -n "$NIXOS_HOST" ]] || {
        error "--host requires a value"
        exit 2
      }
      ;;
    --edit) EDIT=1 ;;
    --no-edit) EDIT=0 ;;
    --yes) NO_PROMPT=1 ;;
    --commit) COMMIT=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
  shift
done

FLAKE="$NIXOS_DIR#$NIXOS_HOST"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/nixos-rebuild-${NIXOS_HOST}-${ACTION}-${TIMESTAMP}.log"

[[ -f "$NIXOS_DIR/flake.nix" ]] || {
  error "flake.nix not found under $NIXOS_DIR"
  exit 2
}
command_exists nix || {
  error "nix is not available"
  exit 2
}
command_exists nixos-rebuild || {
  error "nixos-rebuild is not available"
  exit 2
}
mkdir -p "$LOG_DIR"

info "Target:"
printf "  - action: %s\n" "$ACTION"
printf "  - flake:  %s\n" "$FLAKE"
printf "  - log:    %s\n" "$LOG_FILE"

if ((EDIT)); then
  [[ -n "${EDITOR:-}" ]] || {
    error "\$EDITOR is not set; pass --no-edit or set EDITOR"
    exit 2
  }
  info "Opening $NIXOS_DIR/flake.nix"
  "$EDITOR" "$NIXOS_DIR/flake.nix"
fi

info "Formatting flake sources"
nix fmt "$NIXOS_DIR"

info "Validating flake outputs"
nix flake check --no-build "$NIXOS_DIR"
nix eval --raw "$NIXOS_DIR#nixosConfigurations.${NIXOS_HOST}.config.networking.hostName" >/dev/null

if git -C "$NIXOS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  info "Repository changes:"
  git -C "$NIXOS_DIR" status --short
  git -C "$NIXOS_DIR" diff --stat
  git -C "$NIXOS_DIR" diff --cached --stat
fi

if [[ "$NO_PROMPT" != "1" ]] && ! prompt_confirm "Run '$ACTION' for $NIXOS_HOST?"; then
  warn "Aborted"
  exit 0
fi

REBUILD=(nixos-rebuild "$ACTION" --flake "$FLAKE")
if [[ "$ACTION" != "build" ]]; then
  REBUILD=(sudo "${REBUILD[@]}")
fi

info "Running: ${REBUILD[*]}"
set +e
"${REBUILD[@]}" 2>&1 | tee "$LOG_FILE"
rc=${PIPESTATUS[0]}
set -e

if ((rc != 0)); then
  error "nixos-rebuild $ACTION failed (exit $rc)"
  warn "Full log: $LOG_FILE"
  command_exists notify-send &&
    notify-send -e "NixOS rebuild FAILED" "See $LOG_FILE" --icon=software-update-urgent 2>/dev/null || true
  exit "$rc"
fi

ok "nixos-rebuild $ACTION succeeded"

if ((COMMIT)) && git -C "$NIXOS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -n "$(git -C "$NIXOS_DIR" status --porcelain)" ]] &&
    prompt_confirm "Commit all repository changes?"; then
    git -C "$NIXOS_DIR" add -A
    git -C "$NIXOS_DIR" commit -m "NixOS ${NIXOS_HOST} ${ACTION}"
  fi
fi

command_exists notify-send &&
  notify-send -e "NixOS $ACTION OK" "$NIXOS_HOST" --icon=software-update-available 2>/dev/null || true
ok "Log saved at $LOG_FILE"

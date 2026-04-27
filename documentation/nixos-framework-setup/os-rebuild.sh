#!/usr/bin/env bash
set -euo pipefail

# os-rebuild: Guided NixOS rebuild helper with clean UX.
# Requirements: sudo, $EDITOR set, nixos-rebuild. Optional: alejandra, git, notify-send.
#
# Defaults and env overrides:
#   NIXOS_CONFIG       Path to configuration.nix (default: ~/.config/nixos/configuration.nix;
#                      for a non-default host use e.g. …/hosts/<hostname>/configuration.nix)
#   NIXOS_DIR          Directory containing config (default: dirname of NIXOS_CONFIG)
#   OS_REBUILD_LOG_DIR Where to store logs (default: ~/.cache/os-rebuild)
#   OS_REBUILD_NO_PROMPT=1  Future non-interactive mode (currently unused; reserved)
#
# Behavior:
#   - Validates $EDITOR is set; opens config with sudo -E.
#   - Optionally formats *.nix with alejandra (if installed).
#   - Shows diff (git-based if repo; otherwise message).
#   - Runs nixos-rebuild with -I nixos-config, saves logs, surfaces errors on failure.
#   - On success, optionally commits changes in git repo with current generation as message.
#   - Desktop notifications if notify-send is available.

info()  { printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[err]\033[0m  %s\n" "$*" >&2; }
ok()    { printf "\033[1;32m[ok]\033[0m   %s\n" "$*"; }

prompt_confirm() {
  # Guided prompt; default Yes on empty input.
  # Usage: prompt_confirm "Question?" && do_something
  local reply
  printf "\n%s [Y/n]: " "$*"
  read -r reply || true
  case "${reply:-Y}" in
    Y|y|yes|Yes) return 0 ;;
    N|n|no|No)   return 1 ;;
    *)           return 0 ;;
  esac
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Inputs
NIXOS_CONFIG="${NIXOS_CONFIG:-$HOME/.config/nixos/configuration.nix}"
NIXOS_DIR="${NIXOS_DIR:-"$(dirname "$NIXOS_CONFIG")"}"
LOG_DIR="${OS_REBUILD_LOG_DIR:-$HOME/.cache/os-rebuild}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/nixos-rebuild-$TIMESTAMP.log"

main() {
  # Validate EDITOR
  if [[ -z "${EDITOR:-}" ]]; then
    error "\$EDITOR is not set. Please export EDITOR to your preferred editor."
    error "Example: export EDITOR=vim"
    exit 2
  fi

  # Validate config path
  if [[ ! -f "$NIXOS_CONFIG" ]]; then
    error "NIXOS_CONFIG does not exist: $NIXOS_CONFIG"
    error "Set NIXOS_CONFIG to your configuration.nix path."
    exit 2
  fi

  mkdir -p "$LOG_DIR"

  info "Target configuration:"
  printf "  - nixos-config: %s\n" "$NIXOS_CONFIG"
  printf "  - repo/dir:     %s\n" "$NIXOS_DIR"
  printf "  - log file:     %s\n" "$LOG_FILE"

  # Detect optional tools
  local has_alejandra="no"
  local has_notify="no"
  local has_git="no"
  if command_exists alejandra; then has_alejandra="yes"; fi
  if command_exists notify-send; then has_notify="yes"; fi
  if command_exists git && git -C "$NIXOS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then has_git="yes"; fi

  # Guided confirmation
  info "Planned steps:"
  printf "  1) Open editor with sudo -E to edit configuration\n"
  printf "  2) Optional format with alejandra (if available: %s)\n" "$has_alejandra"
  printf "  3) Show diff of *.nix (git-based if repo: %s)\n" "$has_git"
  printf "  4) Run nixos-rebuild switch (-I nixos-config=...); save logs\n"
  printf "  5) On success, optionally commit in git repo\n"
  printf "  6) Desktop notification (if available: %s)\n" "$has_notify"
  # No confirmation needed before step 1 — proceed directly.

  # Step 1: Open editor with sudo -E
  info "Opening editor: sudo -E $EDITOR \"$NIXOS_CONFIG\""
  sudo -E "$EDITOR" "$NIXOS_CONFIG"

  # Step 2: Optional format
  if [[ "$has_alejandra" == "yes" ]]; then
    info "Formatting *.nix under $NIXOS_DIR with alejandra..."
    if find "$NIXOS_DIR" -type f -name "*.nix" -print0 2>/dev/null | xargs -0 -r alejandra; then
      ok "Formatting complete."
    else
      warn "Formatting encountered issues; continuing."
    fi
  else
    info "alejandra not found; skipping formatting."
  fi

  # Step 3: Show diff
  info "Showing changes to *.nix..."
  if [[ "$has_git" == "yes" ]]; then
    # Show unstaged/staged diffs for *.nix
    if ! git -C "$NIXOS_DIR" diff -U0 -- '*.nix' | sed -e 's/^/[diff] /'; then
      warn "git diff returned non-zero; continuing."
    fi
    if ! prompt_confirm "Continue to rebuild?"; then
      warn "Aborted by user."
      exit 0
    fi
  else
    warn "No git repo detected at $NIXOS_DIR — skipping git diff."
    info "Tip: Initialize a git repo to enable diffs and commit-on-success."
    if ! prompt_confirm "Continue to rebuild without git diff?"; then
      warn "Aborted by user."
      exit 0
    fi
  fi

  # Step 4: Rebuild with logs
  info "Rebuilding NixOS; logging to $LOG_FILE"
  set +e
  sudo nixos-rebuild switch -I "nixos-config=$NIXOS_CONFIG" >"$LOG_FILE" 2>&1
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    error "nixos-rebuild failed (exit $rc). Showing recent errors:"
    # Heuristic: show last 60 lines and grep for 'error' if present
    tail -n 60 "$LOG_FILE" | sed -e 's/^/[log] /'
    if grep -i -n "error" "$LOG_FILE" >/dev/null 2>&1; then
      printf "\n"
      grep -i -n "error" "$LOG_FILE" | tail -n 20 | sed -e 's/^/[err] /'
    fi
    warn "Full log at: $LOG_FILE"
    if [[ "$has_notify" == "yes" ]]; then
      notify-send -e "NixOS rebuild FAILED" "See log: $LOG_FILE" --icon=software-update-urgent 2>/dev/null || true
    fi
    exit $rc
  fi
  ok "nixos-rebuild succeeded."

  # Step 5: Commit-on-success (optional)
  if [[ "$has_git" == "yes" ]]; then
    # Only commit if there are actual changes.
    if ! git -C "$NIXOS_DIR" diff --quiet -- '*.nix'; then
      info "Creating commit for changed *.nix..."
      current="$(nixos-rebuild list-generations | grep current || true)"
      git -C "$NIXOS_DIR" add -A
      if [[ -n "${current:-}" ]]; then
        git -C "$NIXOS_DIR" commit -m "$current" || warn "git commit failed or nothing to commit."
      else
        git -C "$NIXOS_DIR" commit -m "NixOS rebuild" || warn "git commit failed or nothing to commit."
      fi
    else
      info "No *.nix changes detected; skipping commit."
    fi
  fi

  # Step 6: Desktop notify
  if [[ "$has_notify" == "yes" ]]; then
    notify-send -e "NixOS rebuilt OK" --icon=software-update-available 2>/dev/null || true
  fi

  ok "Done. Log saved at: $LOG_FILE"
}

main "$@"


#!/usr/bin/env bash
# Build nixosConfigurations.Go3 on this machine; activate on Go3 over SSH.
#
# Deliberately thinner than scripts/hearth-deploy.sh. Hearth guards Jellyfin,
# the COLD NTFS volume, restic and gitignored intranet config, and pins
# deploys to origin/deploy/hearth. The Go3 kiosk has none of that state: it is
# one cage session running one Chromium. So this builds the checkout, copies,
# and activates — no TUI, no deploy pin, no shared-tree path filter.
set -euo pipefail

info() { printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[err]\033[0m  %s\n" "$*" >&2; }
ok() { printf "\033[1;32m[ok]\033[0m   %s\n" "$*"; }
heading() { printf "\n\033[1m%s\033[0m\n" "$*"; }

NIXOS_DIR="${NIXOS_DIR:-$HOME/.config/nixos}"
FLAKE_OUTPUT="Go3"
FLAKE="${NIXOS_DIR}#${FLAKE_OUTPUT}"
# The `go3` alias comes from home/programs/ssh-go3.nix. Raw MagicDNS is a
# different name and fails host-key checks against the alias's known_hosts
# entry, so prefer the alias and let GO3_SSH_TARGET override it.
TARGET="${GO3_SSH_TARGET:-go3}"
TARGET_HOSTNAME="${GO3_SSH_HOSTNAME:-go3.tail6cd822.ts.net}"
LOG_DIR="${GO3_DEPLOY_LOG_DIR:-$HOME/.cache/go3-deploy}"

SSH_OPTS=(
  -o ConnectTimeout=10
  -o ControlMaster=auto
  -o "ControlPath=$HOME/.ssh/cm-%r@%h:%p"
  -o ControlPersist=10m
  # Without keepalives a ControlPersist master whose TCP connection died
  # silently (Wi-Fi roam, suspend) accepts new sessions and then hangs them.
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=3
)

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

  build           Build #Go3 here. No copy, no activate.
  dry-activate    Build, copy, show what activation would change.
  switch          Build, copy, activate now.
  boot            Build, copy, set as next boot generation.
  status          Branch, reachability, running generation.
  ssh             Open a shell on Go3.
  -h, --help      Show this help.

Environment:
  NIXOS_DIR              Flake directory (default: ~/.config/nixos)
  GO3_SSH_TARGET         ssh destination (default: go3)
  GO3_SSH_HOSTNAME       MagicDNS name for reachability checks
  GO3_DEPLOY_LOG_DIR     Log directory (default: ~/.cache/go3-deploy)

Run this on Tawa (or another strong builder), never on Go3 itself.
EOF
}

refuse_if_on_go3() {
  if [[ "$(hostname)" == "Go3" ]]; then
    error "This is Go3. Build and activate from Tawa with go3-deploy."
    error "Running nixos-rebuild here builds the kiosk on the kiosk."
    exit 2
  fi
}

# Git flakes cannot see untracked files: a new host module that is not staged
# is silently absent from the build. hearth-deploy offers to stage; here we
# only warn, since the kiosk closure is small enough to notice a miss.
warn_untracked() {
  local untracked
  untracked="$(cd "$NIXOS_DIR" && git ls-files --others --exclude-standard -- '*.nix' 2>/dev/null || true)"
  if [[ -n "$untracked" ]]; then
    warn "Untracked .nix files are INVISIBLE to the git flake:"
    printf '  %s\n' $untracked
    warn "git add them before this build means anything."
  fi
}

branch_summary() {
  local branch lane
  branch="$(cd "$NIXOS_DIR" && git branch --show-current 2>/dev/null || echo '?')"
  case "$branch" in
    main) lane="stable" ;;
    dev) lane="unstable" ;;
    *) lane="feature" ;;
  esac
  printf '%s (%s)' "$branch" "$lane"
}

ssh_go3() { ssh "${SSH_OPTS[@]}" "$TARGET" "$@"; }

require_ssh() {
  if ! ssh_go3 -o BatchMode=yes true 2>/dev/null; then
    error "No SSH path to Go3 via '${TARGET}'."
    error "Most likely causes, in order:"
    error "  1. Unknown host key. BatchMode refuses the prompt, so connect once"
    error "     interactively: ssh ${TARGET_HOSTNAME}"
    error "  2. The 'go3' alias is missing — ~/.ssh/config must Include"
    error "     config.d/go3 (home/programs/ssh-go3.nix, needs a Tawa switch)."
    error "  3. Host is down: tailscale status | grep go3"
    error "Override the destination with GO3_SSH_TARGET=wiz@${TARGET_HOSTNAME}"
    return 1
  fi
}

new_log() {
  mkdir -p "$LOG_DIR"
  LOG_FILE="${LOG_DIR}/$(date +%Y%m%d-%H%M%S).log"
}

run_logged() {
  info "\$ $*"
  "$@" 2>&1 | tee -a "$LOG_FILE"
  return "${PIPESTATUS[0]}"
}

run_build() {
  warn_untracked
  heading "Build #${FLAKE_OUTPUT} on $(hostname) — $(branch_summary)"
  if (cd "$NIXOS_DIR" && run_logged nixos-rebuild build --flake "$FLAKE"); then
    ok "Build finished."
    return 0
  fi
  error "Build failed. Full log: $LOG_FILE"
  return 1
}

run_deploy() {
  local action="$1"
  warn_untracked
  require_ssh || return 1
  heading "nixos-rebuild ${action} → Go3 — $(branch_summary)"
  info "Activator is nixos-rebuild --target-host, same as hearth-deploy."
  if (cd "$NIXOS_DIR" && NIX_SSHOPTS="${SSH_OPTS[*]}" run_logged \
      nixos-rebuild "$action" \
      --flake "$FLAKE" \
      --target-host "$TARGET" \
      --use-remote-sudo); then
    ok "nixos-rebuild ${action} succeeded."
    if [[ "$action" == "switch" ]]; then
      ensure_kiosk || true
    fi
    return 0
  fi
  error "nixos-rebuild ${action} failed. Full log: $LOG_FILE"
  # Activation may still have completed: the switch that applied
  # remote-access.nix's --ssh=false cut its own SSH session and exited 255
  # with the new generation live. That is precisely the case where the kiosk
  # needs checking, so check it here too rather than only on success.
  if [[ "$action" == "switch" ]]; then
    ensure_kiosk || true
  fi
  return 1
}

# Getting the kiosk back after a switch, whatever stopped it.
#
# profiles/kiosk.nix restarts cage-tty1 when the unit itself changes, but that
# is only one of the ways a deploy takes the screen down. Observed 2026-09-01
# on a switch that changed nothing at all: switch-to-configuration started
# getty@tty1.service, which Conflicts with cage-tty1, so systemd stopped the
# kiosk -- and because the cage unit was unchanged, nothing restarted it. The
# wall sat blank behind a "succeeded" deploy.
#
# So this does not merely report: if the kiosk is not back by the deadline it
# starts it, which is what the card asked for -- activation brings the kiosk
# back on its own -- and it works regardless of what stopped it.
kiosk_state() {
  # `systemctl is-active` exits non-zero for anything but active, so its exit
  # status cannot stand in for "the ssh failed"; take the word it prints.
  local out
  out="$(ssh_go3 systemctl is-active cage-tty1 2>/dev/null || true)"
  [[ -n "$out" ]] || out="unreachable"
  printf '%s' "$out"
}

kiosk_procs() {
  # `pgrep -c` prints 0 *and* exits 1 when nothing matches, so read the
  # number and judge on the number.
  local out
  out="$(ssh_go3 pgrep -c chromium 2>/dev/null || true)"
  [[ "$out" =~ ^[0-9]+$ ]] || out=0
  printf '%s' "$out"
}

# cage-tty1 reports active before Chromium has spawned, so a live unit is not
# a live kiosk; both have to be true.
kiosk_up() {
  [[ "$(kiosk_state)" == "active" ]] && [[ "$(kiosk_procs)" -gt 0 ]]
}

await_kiosk() {
  local deadline=$((SECONDS + $1))
  while ((SECONDS < deadline)); do
    if kiosk_up; then
      return 0
    fi
    sleep 5
  done
  return 1
}

ensure_kiosk() {
  info "Confirming the kiosk came back (up to 60s)..."
  if await_kiosk 60; then
    ok "Kiosk is up: cage-tty1 active, $(kiosk_procs) chromium processes."
    return 0
  fi

  warn "Kiosk did not come back on its own (cage-tty1: $(kiosk_state)). Starting it."
  # Starting cage-tty1 also stops getty@tty1, which Conflicts with it, so this
  # takes tty1 back in one step.
  if ! ssh_go3 sudo systemctl start cage-tty1; then
    error "Could not start cage-tty1 over SSH. The wall screen is blank."
    return 1
  fi
  if await_kiosk 60; then
    ok "Kiosk recovered: cage-tty1 active, $(kiosk_procs) chromium processes."
    return 0
  fi

  error "Kiosk still down after a restart (cage-tty1: $(kiosk_state), chromium: $(kiosk_procs))."
  error "Check: $(basename "$0") ssh -- journalctl -u cage-tty1 -n 30"
  return 1
}

run_status() {
  heading "Go3 status"
  printf '  builder branch : %s\n' "$(branch_summary)"
  printf '  ssh target     : %s (%s)\n' "$TARGET" "$TARGET_HOSTNAME"
  if ssh_go3 -o BatchMode=yes true 2>/dev/null; then
    printf '  reachable      : yes\n'
    printf '  hostname       : %s\n' "$(ssh_go3 hostname 2>/dev/null || echo '?')"
    printf '  generation     : %s\n' "$(ssh_go3 readlink /run/current-system 2>/dev/null || echo '?')"
    printf '  kiosk          : %s\n' "$(ssh_go3 systemctl is-active cage-tty1 2>/dev/null || echo 'inactive')"
    printf '  tailscale      : %s\n' "$(ssh_go3 systemctl is-active tailscaled 2>/dev/null || echo '?')"
  else
    printf '  reachable      : NO\n'
  fi
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    -h | --help | "") usage; [[ -n "$cmd" ]] || exit 2 ;;
    ssh) refuse_if_on_go3; shift; exec ssh "${SSH_OPTS[@]}" "$TARGET" "$@" ;;
    status) refuse_if_on_go3; run_status ;;
    build) refuse_if_on_go3; new_log; run_build ;;
    dry-activate | switch | boot) refuse_if_on_go3; new_log; run_deploy "$cmd" ;;
    *) error "Unknown command: $cmd"; usage; exit 2 ;;
  esac
}

main "$@"

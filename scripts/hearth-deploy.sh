#!/usr/bin/env bash
# Build nixosConfigurations.Hearth on this machine; activate on Hearth over SSH.
set -euo pipefail

info() { printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[err]\033[0m  %s\n" "$*" >&2; }
ok() { printf "\033[1;32m[ok]\033[0m   %s\n" "$*"; }
heading() { printf "\n\033[1m%s\033[0m\n" "$*"; }

NIXOS_HOST="Hearth"
TARGET_USER="wiz"
TARGET_HOSTNAME="${HEARTH_SSH_HOSTNAME:-hearth.tail6cd822.ts.net}"
# Use the Host hearth alias so known_hosts / ssh config match. Raw MagicDNS
# (hearth.tail6cd822.ts.net) is a different name and fails host-key checks.
TARGET="${HEARTH_SSH_TARGET:-hearth}"
FLAKE_OUTPUT="Hearth"

DOC_SSH="unknown"
DOC_SSH_KIND=""
DOC_SUDO="unknown"
DOC_TRUST="unknown"
DOC_REMOTE=""
DOC_HINT=""

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

has_gum() {
  command_exists gum && [[ -t 1 ]] && [[ -t 0 ]]
}

short_home() {
  local p="$1"
  local home="${HOME%/}"
  if [[ -n "$home" && "$p" == "$home"/* ]]; then
    printf '~/%s' "${p#"$home"/}"
  else
    printf '%s' "$p"
  fi
}

short_store() {
  local p="$1"
  if [[ "$p" =~ /nix/store/([a-z0-9]{7})[a-z0-9]+-(.+)$ ]]; then
    printf '%s…-%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf '%s' "$p"
  fi
}

term_width() {
  local w="${COLUMNS:-}"
  if [[ -z "$w" ]] && [[ -t 1 ]]; then
    w="$(tput cols 2>/dev/null || true)"
  fi
  if [[ -z "$w" || "$w" -lt 40 ]]; then
    w=72
  fi
  if [[ "$w" -gt 88 ]]; then
    w=88
  fi
  printf '%s' "$w"
}

usage() {
  cat <<'EOF'
Build #Hearth on this machine and activate it on Hearth over OpenSSH.

Usage:
  hearth-deploy                 Interactive TUI
  hearth-deploy status          Connection + flake status
  hearth-deploy doctor          Probe SSH, sudo, and trusted-users
  hearth-deploy health          Post-activate probes (sshd, Tailscale, Jellyfin, COLD)
  hearth-deploy build           Build only (no copy, no activate)
  hearth-deploy dry-activate    Build, copy, show activation diff
  hearth-deploy switch          Pick source, then build, copy, activate, health
  hearth-deploy boot            Build, copy, set next boot generation
  hearth-deploy ssh             Open a shell on Hearth

Options:
  --yes                   Skip confirmations
  --no-stage              Do not offer to git-add untracked flake inputs
  --from-checkout         Activate the builder worktree (skips the switch source menu).
  -h, --help              Show this help

Environment:
  NIXOS_DIR               Flake directory (default: ~/.config/nixos)
  HEARTH_SSH_TARGET       Override ssh destination (default: hearth)
  HEARTH_SSH_HOSTNAME     Override MagicDNS / IP written into ~/.ssh/config.d/hearth
  HEARTH_DEPLOY_LOG_DIR   Log directory (default: ~/.cache/hearth-deploy)
  HEARTH_DEPLOY_ALLOW_SHARED=1  Allow common/ home/ profiles/ flake.nix flake.lock in the deploy range

Run this on Tawa (or another strong builder). Do not run switch/boot on Hearth.
EOF
}

is_activation() {
  case "$1" in
    dry-activate | switch | boot) return 0 ;;
    *) return 1 ;;
  esac
}

# The flake is the builder's checkout. main = stable, dev = daily/unstable.
repo_branch() {
  command_exists git || {
    printf 'unknown'
    return
  }
  git -C "$NIXOS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf 'unknown'
    return
  }
  local ref
  ref="$(git -C "$NIXOS_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -n "$ref" ]]; then
    printf '%s' "$ref"
    return
  fi
  local short
  short="$(git -C "$NIXOS_DIR" rev-parse --short HEAD 2>/dev/null || printf '?')"
  printf 'detached@%s' "$short"
}

branch_lane() {
  case "$1" in
    main) printf 'stable' ;;
    dev) printf 'unstable' ;;
    detached@*) printf 'detached' ;;
    unknown) printf 'unknown' ;;
    *) printf 'topic' ;;
  esac
}

branch_summary() {
  local branch lane
  branch="$(repo_branch)"
  lane="$(branch_lane "$branch")"
  case "$lane" in
    stable) printf '%s (stable)' "$branch" ;;
    unstable) printf '%s (unstable — daily host work)' "$branch" ;;
    detached) printf '%s (not a branch)' "$branch" ;;
    topic) printf '%s (topic — not main/dev)' "$branch" ;;
    *) printf '%s' "$branch" ;;
  esac
}

# switch/boot/dry-activate default to origin/deploy/hearth, not Tawa's dirty dest.
fetch_deploy_pin() {
  git -C "$NIXOS_DIR" fetch origin deploy/hearth:refs/remotes/origin/deploy/hearth
}

activation_rev() {
  if (( FROM_CHECKOUT )); then
    git -C "$NIXOS_DIR" rev-parse HEAD
  else
    git -C "$NIXOS_DIR" rev-parse origin/deploy/hearth
  fi
}

activation_flake() {
  if (( FROM_CHECKOUT )); then
    printf '%s#%s' "$NIXOS_DIR" "$FLAKE_OUTPUT"
    return
  fi
  local rev
  rev="$(git -C "$NIXOS_DIR" rev-parse origin/deploy/hearth)"
  printf 'git+file://%s?rev=%s#%s' "$NIXOS_DIR" "$rev" "$FLAKE_OUTPUT"
}

activation_summary() {
  if (( FROM_CHECKOUT )); then
    printf 'builder checkout %s (ESCAPE HATCH --from-checkout)' "$(branch_summary)"
    return
  fi
  local rev
  rev="$(git -C "$NIXOS_DIR" rev-parse --short origin/deploy/hearth 2>/dev/null || printf '?')"
  printf 'origin/deploy/hearth (%s)' "$rev"
}

# Interactive switch (and TUI Switch): pick checkout, pin, or FF pin to origin/dev.
# --from-checkout skips this. --yes keeps the pin (no FF, no checkout).
# Answers in SWITCH_SOURCE, not on stdout: has_gum needs a tty on fd 1, and the
# text fallback has to print the menu where the operator can see it.
choose_switch_source() {
  SWITCH_SOURCE="pin"
  if [[ "$NO_PROMPT" == "1" ]]; then
    return 0
  fi

  local branch pin_rev
  branch="$(repo_branch)"
  pin_rev="$(git -C "$NIXOS_DIR" rev-parse --short origin/deploy/hearth 2>/dev/null || printf '?')"

  local opt_current="Current branch (${branch})"
  local opt_pin="Pinned branch (hearthDeploy / origin/deploy/hearth @ ${pin_rev})"
  local opt_ff="Fast-forward deploy/hearth to origin/dev and use that"

  local pick=""
  if has_gum; then
    pick="$(
      gum choose \
        --header "Hearth switch source" \
        --cursor "→ " \
        "$opt_current" \
        "$opt_pin" \
        "$opt_ff"
    )" || return 1
  else
    printf '\nSwitch source:\n'
    printf '  [1] %s\n' "$opt_current"
    printf '  [2] %s\n' "$opt_pin"
    printf '  [3] %s\n' "$opt_ff"
    printf 'Choice [2]: '
    read -r pick || true
  fi

  case "$pick" in
    1 | current | "$opt_current") SWITCH_SOURCE="checkout" ;;
    3 | ff | ff-dev | dev | "$opt_ff") SWITCH_SOURCE="ff-dev" ;;
    2 | pin | hearthDeploy | "" | "$opt_pin") SWITCH_SOURCE="pin" ;;
    *)
      error "Unknown switch source: ${pick}"
      return 1
      ;;
  esac
}

fast_forward_deploy_pin_to_dev() {
  info "Fetching origin/dev and origin/deploy/hearth"
  git -C "$NIXOS_DIR" fetch origin dev:refs/remotes/origin/dev || {
    error "Could not fetch origin/dev."
    return 1
  }
  git -C "$NIXOS_DIR" fetch origin deploy/hearth:refs/remotes/origin/deploy/hearth || {
    error "Could not fetch origin/deploy/hearth."
    return 1
  }

  local dev_rev pin_rev
  dev_rev="$(git -C "$NIXOS_DIR" rev-parse origin/dev)"
  pin_rev="$(git -C "$NIXOS_DIR" rev-parse origin/deploy/hearth)"
  if [[ "$dev_rev" == "$pin_rev" ]]; then
    ok "origin/deploy/hearth already at origin/dev ($(git -C "$NIXOS_DIR" rev-parse --short origin/dev))"
    return 0
  fi

  info "git push origin origin/dev:refs/heads/deploy/hearth"
  git -C "$NIXOS_DIR" push origin origin/dev:refs/heads/deploy/hearth || {
    error "Fast-forward of deploy/hearth to origin/dev failed (pin is not an ancestor, or push was refused). Not force-pushing."
    return 1
  }
  git -C "$NIXOS_DIR" fetch origin deploy/hearth:refs/remotes/origin/deploy/hearth
  ok "origin/deploy/hearth is now $(git -C "$NIXOS_DIR" rev-parse --short origin/deploy/hearth) (origin/dev)"
}

refuse_shared_deploy_paths() {
  local tip="$1"
  local hit
  if ! git -C "$NIXOS_DIR" rev-parse --verify origin/main >/dev/null 2>&1; then
    git -C "$NIXOS_DIR" fetch origin main:refs/remotes/origin/main || true
  fi
  hit="$(git -C "$NIXOS_DIR" diff --name-only origin/main..."$tip" -- common home profiles flake.nix flake.lock 2>/dev/null || true)"
  [[ -z "$hit" ]] && return 0
  if [[ "${HEARTH_DEPLOY_ALLOW_SHARED:-0}" == "1" ]]; then
    warn "Shared-tree paths in origin/main...${tip} (HEARTH_DEPLOY_ALLOW_SHARED=1):"
    printf '    %s\n' $hit
    return 0
  fi
  if git -C "$NIXOS_DIR" log origin/main.."$tip" --pretty=%B 2>/dev/null | grep -q '^Hearth-Deploy: allow-shared$'; then
    warn "Shared-tree paths allowed by trailer Hearth-Deploy: allow-shared."
    return 0
  fi
  error "Refusing Hearth deploy: origin/main...${tip} touches shared tree:"
  printf '    %s\n' $hit
  error "Fast-forward deploy/hearth with Hearth-only commits, or HEARTH_DEPLOY_ALLOW_SHARED=1, or trailer Hearth-Deploy: allow-shared."
  return 1
}

local_hostname() {
  hostname
}

refuse_if_on_hearth() {
  local here
  here="$(local_hostname)"
  if [[ "$here" == "Hearth" ]]; then
    error "This is Hearth. Build and activate from Tawa with hearth-deploy."
    error "For the one-time trust/sudo bootstrap only: os-rebuild switch --no-commit"
    return 1
  fi
}

setup_ssh() {
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/hearth-deploy"
  mkdir -p "$cache"
  CONTROL_PATH="$cache/ssh-%C"
  SSH_OPTS=(
    -o Port=22
    -o ControlMaster=auto
    -o "ControlPath=$CONTROL_PATH"
    -o ControlPersist=10m
    -o IdentitiesOnly=no
  )
  export NIX_SSHOPTS="${SSH_OPTS[*]}"
}

ssh_hearth() {
  ssh "${SSH_OPTS[@]}" "$TARGET" "$@"
}

ensure_ssh_include() {
  local ssh_dir="${HOME}/.ssh"
  local config="$ssh_dir/config"
  local fragment="$ssh_dir/config.d/hearth"
  mkdir -p "$ssh_dir/config.d"
  chmod 700 "$ssh_dir" 2>/dev/null || true

  if [[ ! -f "$fragment" ]]; then
    cat >"$fragment" <<EOF
Host hearth
  HostName ${TARGET_HOSTNAME}
  User ${TARGET_USER}
  Port 22
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
EOF
    chmod 600 "$fragment"
  fi

  if [[ -f "$config" ]] && grep -Eq '^[[:space:]]*Include[[:space:]]+(~/.ssh/)?config\.d/(hearth|\*)' "$config"; then
    return 0
  fi
  if [[ -f "$config" ]] && grep -Eq '^Host[[:space:]]+hearth([[:space:]]|$)' "$config"; then
    return 0
  fi

  touch "$config"
  chmod 600 "$config"
  {
    printf '\n# added by hearth-deploy\n'
    printf 'Include config.d/hearth\n'
  } >>"$config"
  ok "Added Include config.d/hearth to $(short_home "$config")"
}

filter_rebuild_output() {
  local width
  width="$(term_width)"
  awk -v width="$width" '
    BEGIN { skip = 0 }

    function squash(s,    out, rest, hash) {
      out = ""
      rest = s
      while (match(rest, /\/nix\/store\/[0-9a-z]{20,}/)) {
        hash = substr(rest, RSTART + 11, 7)
        out = out substr(rest, 1, RSTART - 1) "/nix/store/" hash "…"
        rest = substr(rest, RSTART + RLENGTH)
      }
      return out rest
    }

    function wrap(s,    chunk, i, pad) {
      s = squash(s)
      pad = ""
      while (length(s) > width) {
        chunk = substr(s, 1, width)
        i = width
        while (i > 24 && substr(chunk, i, 1) != " ") {
          i--
        }
        if (i <= 24) {
          i = width
        }
        print pad substr(s, 1, i)
        s = substr(s, i + 1)
        sub(/^[[:space:]]+/, "", s)
        pad = "  "
      }
      if (s != "") {
        print pad s
      }
    }

    /^warning: Git tree / { next }
    /^trace: / { next }
    /^evaluation warning: .system. has been renamed/ { next }
    /^evaluation warning: crane / { skip = 1; next }
    skip && (/^[[:space:]]/ || $0 == "") { next }
    /To find the source of this warning/ { next }
    /NIX_ABORT_ON_WARN/ { next }
    { skip = 0; wrap($0) }
  '
}

run_logged() {
  local rc
  set +e
  "$@" 2>&1 | tee "$LOG_FILE" | filter_rebuild_output
  rc=${PIPESTATUS[0]}
  set -e
  return "$rc"
}

confirm() {
  local question="$1"
  local default="${2:-no}"
  if [[ "$NO_PROMPT" == "1" ]]; then
    return 0
  fi
  if has_gum; then
    if [[ "$default" == "yes" ]]; then
      gum confirm --default=true "$question"
    else
      gum confirm --default=false "$question"
    fi
    return
  fi
  local prompt reply
  if [[ "$default" == "yes" ]]; then
    prompt="[Y/n]"
  else
    prompt="[y/N]"
  fi
  printf "\n%s %s: " "$question" "$prompt"
  read -r reply || true
  if [[ -z "$reply" ]]; then
    [[ "$default" == "yes" ]]
    return
  fi
  case "$reply" in
    Y | y | yes | Yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

dirty_count() {
  command_exists git || {
    printf '0'
    return
  }
  git -C "$NIXOS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf '0'
    return
  }
  git -C "$NIXOS_DIR" status --porcelain | wc -l
}

hardware_dirty() {
  command_exists git || return 1
  git -C "$NIXOS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local files
  files="$(
    git -C "$NIXOS_DIR" status --porcelain -- \
      "hosts/${NIXOS_HOST}/hardware-configuration.nix" \
      2>/dev/null || true
  )"
  [[ -n "$files" ]]
}

untracked_flake_inputs() {
  command_exists git || return 0
  git -C "$NIXOS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local line status path
  UNTRACKED=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    status="${line:0:2}"
    path="${line:3}"
    [[ "$status" == "??" ]] || continue
    case "$path" in
      documentation/* | scripts/* | .claude/* | *.md) continue ;;
    esac
    UNTRACKED+=("$path")
  done < <(git -C "$NIXOS_DIR" status --porcelain=v1 --untracked-files=all)
}

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

# After activate: copy gitignored widget config.nix onto Hearth for restic.
# Do not git add those files. Skip widgets that have no local config.nix.
copy_intranet_config_for_restic() {
  local base="$NIXOS_DIR/hosts/Hearth/intranet/config"
  local remote_dir="/var/lib/hearth-intranet/config"
  local widget src copied=0
  ssh_hearth -o BatchMode=yes sudo mkdir -p "$remote_dir" || return 1
  for widget in clock weather transit health gallery calendar alerts; do
    src="$base/$widget/config.nix"
    [[ -f "$src" ]] || continue
    scp -q "$src" "${TARGET}:/tmp/hearth-${widget}.nix" || return 1
    ssh_hearth -o BatchMode=yes sudo mv "/tmp/hearth-${widget}.nix" "${remote_dir}/${widget}.nix" || return 1
    ssh_hearth -o BatchMode=yes sudo chmod 0640 "${remote_dir}/${widget}.nix" || return 1
    copied=$((copied + 1))
  done
  ok "Copied ${copied} intranet config.nix file(s) to ${remote_dir} for restic."
}

offer_stage_untracked() {
  ((STAGE == 0)) && return 0
  untracked_flake_inputs
  ((${#UNTRACKED[@]} == 0)) && return 0

  heading "Untracked flake inputs"
  warn "A Git flake cannot see these until they are staged:"
  printf '    - %s\n' "${UNTRACKED[@]}"
  if ! confirm "Stage these files and continue?" "yes"; then
    error "Refusing to build while configuration inputs are untracked."
    return 1
  fi
  git -C "$NIXOS_DIR" add -- "${UNTRACKED[@]}"
  ok "Staged ${#UNTRACKED[@]} file(s)."
}

status_dot() {
  case "$1" in
    ok) printf '\033[1;32m●\033[0m' ;;
    password) printf '\033[1;33m●\033[0m' ;;
    missing | fail) printf '\033[1;31m●\033[0m' ;;
    *) printf '\033[1;33m●\033[0m' ;;
  esac
}

status_text() {
  case "$1" in
    ok) printf 'ok' ;;
    password) printf 'needs password' ;;
    missing) printf 'not configured' ;;
    fail) printf 'failed' ;;
    *) printf 'not checked' ;;
  esac
}

collect_status_body() {
  local here dirty flake_state remote
  here="$(local_hostname)"
  dirty="$(dirty_count)"
  if [[ "$dirty" == "0" ]]; then
    flake_state="clean"
  else
    flake_state="dirty (${dirty})"
  fi
  if [[ -n "$DOC_REMOTE" ]]; then
    remote="$(short_store "$DOC_REMOTE")"
  else
    remote="—"
  fi

  printf '%s\n' \
    "flake     $(short_home "$NIXOS_DIR")   ${flake_state}" \
    "branch    $(branch_summary)" \
    "builder   ${here}" \
    "target    ${TARGET}" \
    "ssh       $(status_text "$DOC_SSH")${DOC_SSH_KIND:+  $DOC_SSH_KIND}" \
    "sudo      $(status_text "$DOC_SUDO")" \
    "trusted   $(status_text "$DOC_TRUST")" \
    "remote    ${remote}"
}

render_status() {
  local body width
  body="$(collect_status_body)"
  width="$(term_width)"

  if has_gum; then
    gum style \
      --border rounded \
      --border-foreground "#2FC7BE" \
      --foreground "#C5FBFC" \
      --padding "0 1" \
      --width "$width" \
      $'hearth-deploy\nbuild here → switch on Hearth\n\n'"$body"
  else
    heading "hearth-deploy"
    printf '%s\n' "$body"
  fi

  if [[ -n "$DOC_HINT" ]]; then
    printf '\n'
    warn "$DOC_HINT"
  fi
  if hardware_dirty; then
    printf '\n'
    warn "Hearth hardware/host.nix is dirty — prefer Boot, then reboot Hearth."
  fi
}

run_healthcheck() {
  local script="$NIXOS_DIR/scripts/hearth-healthcheck.sh"
  heading "Health check on Hearth ($(branch_summary))"
  if [[ ! -f "$script" ]]; then
    error "Missing $(short_home "$script") — git-add it so the flake (and this checkout) can see it."
    return 1
  fi
  if [[ "$DOC_SSH" != "ok" ]]; then
    run_doctor || true
  fi
  if [[ "$DOC_SSH" != "ok" ]]; then
    error "No SSH path to Hearth; fix doctor before health."
    return 1
  fi
  info "ssh ${TARGET} sudo bash -s < $(short_home "$script")"
  if ssh_hearth -o BatchMode=yes sudo bash -s <"$script"; then
    ok "Hearth health check passed"
    return 0
  fi
  error "Hearth health check failed. Previous generation is still in systemd-boot; use hearth-deploy boot or pick it at the console."
  return 1
}

run_doctor() {
  DOC_HINT=""
  ensure_ssh_include

  local ssh_err
  ssh_err="$(ssh_hearth -o BatchMode=yes -o ConnectTimeout=8 true 2>&1)" || {
    DOC_SSH="fail"
    DOC_SSH_KIND=""
    DOC_SUDO="fail"
    DOC_TRUST="fail"
    DOC_REMOTE=""
    if [[ "$ssh_err" == *"Host key verification failed"* ]]; then
      DOC_HINT="Host key check failed for ${TARGET}. Trust the key under this name (ssh hearth) or connect via the Host hearth alias, not raw MagicDNS."
    elif [[ "$ssh_err" == *"Connection timed out"* || "$ssh_err" == *"Connection refused"* || "$ssh_err" == *"Could not resolve"* ]]; then
      DOC_HINT="Cannot reach ${TARGET} on port 22. Use OpenSSH to sshd, not Tailscale SSH."
    else
      DOC_HINT="SSH to ${TARGET} failed: ${ssh_err%%$'\n'*}"
    fi
    return 1
  }
  DOC_SSH="ok"

  local report
  report="$(
    ssh_hearth -o BatchMode=yes bash -s <<'EOS' || true
set +e
echo "hostname=$(hostname)"
echo "system=$(readlink -f /run/current-system 2>/dev/null)"
if sudo -n true >/dev/null 2>&1; then
  echo "sudo=ok"
else
  echo "sudo=password"
fi
trusted=""
if command -v nix >/dev/null 2>&1; then
  trusted="$(nix config show 2>/dev/null | sed -n 's/^trusted-users = //p')"
  if [ -z "$trusted" ]; then
    trusted="$(nix show-config 2>/dev/null | sed -n 's/^trusted-users = //p')"
  fi
fi
echo "trusted-users=$trusted"
parent="$(ps -o comm= -p "$PPID" 2>/dev/null | tr -d '[:space:]')"
echo "ssh-parent=$parent"
EOS
  )" || true

  DOC_REMOTE="$(printf '%s\n' "$report" | sed -n 's/^system=//p' | tail -n1)"
  case "$(printf '%s\n' "$report" | sed -n 's/^sudo=//p' | tail -n1)" in
    ok) DOC_SUDO="ok" ;;
    password) DOC_SUDO="password" ;;
    *) DOC_SUDO="unknown" ;;
  esac

  local trusted parent
  trusted="$(printf '%s\n' "$report" | sed -n 's/^trusted-users=//p' | tail -n1)"
  if printf ' %s ' "$trusted" | grep -qE ' (@wheel|wiz) '; then
    DOC_TRUST="ok"
  elif [[ -z "$trusted" ]]; then
    DOC_TRUST="unknown"
  else
    DOC_TRUST="missing"
  fi

  parent="$(printf '%s\n' "$report" | sed -n 's/^ssh-parent=//p' | tail -n1)"
  case "$parent" in
    sshd | sshd-session | *sshd*) DOC_SSH_KIND="sshd" ;;
    *tailscale*) DOC_SSH_KIND="tailscale-ssh" ;;
    *) DOC_SSH_KIND="${parent:-unknown}" ;;
  esac

  if [[ "$DOC_SSH_KIND" == "tailscale-ssh" ]]; then
    DOC_HINT="Connected via Tailscale SSH. nix copy wants sshd on port 22."
  fi
  if [[ "$DOC_TRUST" == "missing" ]]; then
    DOC_HINT="Hearth trusted-users lacks @wheel. Switch remote-access.nix on Hearth once."
  fi
  if [[ "$DOC_SUDO" == "password" ]]; then
    DOC_HINT="Hearth sudo still needs a password. Switch remote-access.nix on Hearth once."
  fi

  return 0
}

print_status_report() {
  render_status
  if [[ "$DOC_SSH" == "ok" && "$DOC_TRUST" == "ok" && "$DOC_SUDO" == "ok" ]]; then
    printf '\n'
    ok "Ready to deploy from $(local_hostname) to Hearth."
  fi
}

choose_action() {
  if has_gum; then
    gum choose \
      --header "Action" \
      --cursor "→ " \
      "Build" \
      "Dry-activate" \
      "Switch" \
      "Boot" \
      "Health" \
      "Recheck" \
      "SSH" \
      "Quit"
    return
  fi

  printf '\n  [b] Build          [d] Dry-activate    [s] Switch\n'
  printf '  [o] Boot           [e] Health          [r] Recheck\n'
  printf '  [h] SSH            [q] Quit\n'
  printf '\nAction: '
  local reply
  read -r reply || true
  case "$reply" in
    b | B | build | Build) printf 'Build' ;;
    d | D | dry | Dry-activate) printf 'Dry-activate' ;;
    s | S | switch | Switch) printf 'Switch' ;;
    o | O | boot | Boot) printf 'Boot' ;;
    e | E | health | Health) printf 'Health' ;;
    r | R | recheck | Recheck) printf 'Recheck' ;;
    h | H | ssh | SSH) printf 'SSH' ;;
    q | Q | quit | Quit | '') printf 'Quit' ;;
    *) printf 'Quit' ;;
  esac
}

run_build() {
  offer_stage_untracked
  require_local_intranet_config
  heading "Build #Hearth on $(local_hostname)"
  info "nixos-rebuild build --flake ${FLAKE} --impure"
  if (cd "$NIXOS_DIR" && run_logged nixos-rebuild build --flake "$FLAKE" --impure); then
    ok "Build finished. Store path is in ./result (if cwd is the flake) or the nixos-rebuild result link."
    return 0
  fi
  error "Build failed. Full log: $(short_home "$LOG_FILE")"
  return 1
}

run_deploy() {
  local action="$1"
  # Shadowed so a source picked for one switch does not leak into later TUI actions.
  local FROM_CHECKOUT="$FROM_CHECKOUT"
  offer_stage_untracked
  require_local_intranet_config

  if [[ "$DOC_SSH" != "ok" ]]; then
    run_doctor || true
  fi
  if [[ "$DOC_SSH" != "ok" ]]; then
    error "No SSH path to Hearth; fix doctor before ${action}."
    return 1
  fi

  if [[ "$action" == "switch" ]] && ! (( FROM_CHECKOUT )); then
    fetch_deploy_pin || true
    choose_switch_source || return 1
    case "$SWITCH_SOURCE" in
      checkout) FROM_CHECKOUT=1 ;;
      ff-dev) fast_forward_deploy_pin_to_dev || return 1 ;;
      pin) ;;
      *)
        error "Unknown switch source: ${SWITCH_SOURCE}"
        return 1
        ;;
    esac
  fi

  if ! (( FROM_CHECKOUT )); then
    fetch_deploy_pin || {
      error "Could not fetch origin/deploy/hearth. Create that pin or pass --from-checkout."
      return 1
    }
  else
    warn "Activating the builder checkout, not origin/deploy/hearth."
  fi

  local tip
  tip="$(activation_rev)"
  refuse_shared_deploy_paths "$tip" || return 1

  local act_flake
  act_flake="$(activation_flake)"

  if [[ "$action" == "switch" ]] && hardware_dirty && (( FROM_CHECKOUT )); then
    warn "Hardware/host files changed. Boot + reboot is safer than switch."
    if ! confirm "Still switch Hearth from $(activation_summary)?" "no"; then
      return 0
    fi
  elif is_activation "$action"; then
    if (( FROM_CHECKOUT )); then
      warn "Hearth will activate $(activation_summary). Builder checkout is $(branch_summary)."
    else
      info "Hearth will activate $(activation_summary). Builder checkout is $(branch_summary)."
    fi
    if ! confirm "Run '${action}' on Hearth from $(activation_summary)? Build stays on $(local_hostname)." "no"; then
      return 0
    fi
  fi

  local before=""
  if [[ "$action" == "switch" ]]; then
    before="$(ssh_hearth -o BatchMode=yes readlink -f /run/current-system 2>/dev/null || true)"
  fi

  heading "${action} on Hearth (build on $(local_hostname), $(activation_summary))"
  info "nixos-rebuild ${action} --flake ${act_flake} --impure --target-host ${TARGET} --use-remote-sudo"
  info "Activator is nixos-rebuild --target-host (deploy-rs cannot boot; same path filter)."

  local -a cmd=(
    nixos-rebuild "$action"
    --flake "$act_flake"
    --impure
    --target-host "$TARGET"
    --use-remote-sudo
  )

  if (cd "$NIXOS_DIR" && run_logged "${cmd[@]}"); then
    ok "nixos-rebuild ${action} succeeded"
  else
    error "nixos-rebuild ${action} failed. Full log: $(short_home "$LOG_FILE")"
    warn "If SSH dropped, reconnect and: ssh ${TARGET} readlink /run/current-system"
    return 1
  fi

  if [[ "$action" == "switch" || "$action" == "boot" ]]; then
    copy_intranet_config_for_restic || warn "Intranet config.nix copy for restic failed."
  fi

  if [[ "$action" == "boot" ]]; then
    printf "  Installed as Hearth's next boot generation. Reboot Hearth when ready.\n"
    info "Skipped live health check (boot generation is not running until Hearth reboots)."
  fi

  if [[ "$action" == "switch" ]]; then
    local after=""
    after="$(ssh_hearth -o BatchMode=yes readlink -f /run/current-system 2>/dev/null || true)"
    heading "Remote system"
    printf "  %s\n" "$(short_store "${after:-unknown}")"
    if [[ -n "$before" && -n "$after" && -e "$before" && -e "$after" && "$before" != "$after" ]]; then
      heading "Closure changes"
      nix store diff-closures "$before" "$after" | filter_rebuild_output || true
    fi
    if ! run_healthcheck; then
      error "Activate succeeded but health check failed — do not treat this generation as good."
      HEARTH_NOTIFY_BRANCH="$(repo_branch)" \
        HEARTH_NOTIFY_LANE="$(branch_lane "$(repo_branch)")" \
        HEARTH_NOTIFY_GENERATION="$(short_store "${after:-unknown}")" \
        HEARTH_NOTIFY_LOG="$(short_home "$LOG_FILE")" \
        bash "$NIXOS_DIR/scripts/hearth-notify.sh" health-fail || true
      return 1
    fi

    notify_hearth_if_visible "Hearth switch OK" "$(short_store "${after:-activated}")"
  fi

  command_exists notify-send &&
    notify-send -e "Hearth ${action} OK" "$TARGET" \
      --icon=software-update-available 2>/dev/null || true
}

# Switch only: tell the seated Hyprland session. Skip SDDM, SSH-only, or DPMS-off.
notify_hearth_if_visible() {
  local summary="$1"
  local body="$2"
  ssh_hearth -o BatchMode=yes bash -s -- "$summary" "$body" <<'EOS' || true
set +e
summary="$1"
body="$2"
uid="$(id -u)"
runtime="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
export XDG_RUNTIME_DIR="$runtime"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime}/bus"

graphical=0
if command -v loginctl >/dev/null 2>&1; then
  for sid in $(loginctl show-user "$USER" -p Sessions --value 2>/dev/null); do
    [ -n "$sid" ] || continue
    class="$(loginctl show-session "$sid" -p Class --value 2>/dev/null)"
    typ="$(loginctl show-session "$sid" -p Type --value 2>/dev/null)"
    state="$(loginctl show-session "$sid" -p State --value 2>/dev/null)"
    [ "$class" = user ] || continue
    case "$typ" in
      wayland | x11) ;;
      *) continue ;;
    esac
    case "$state" in
      active | online) graphical=1; break ;;
    esac
  done
fi
[ "$graphical" = 1 ] || exit 0
[ -S "${runtime}/bus" ] || exit 0

json="$(hyprctl -i 0 monitors -j 2>/dev/null)" || exit 0
awake=0
if command -v jq >/dev/null 2>&1; then
  awake="$(printf '%s' "$json" | jq '[.[] | select((.dpmsStatus // false) == true and (.disabled // false) != true)] | length' 2>/dev/null)" || awake=0
elif printf '%s' "$json" | grep -q '"dpmsStatus":[[:space:]]*true'; then
  awake=1
fi
[ "$awake" -gt 0 ] 2>/dev/null || exit 0

command -v notify-send >/dev/null 2>&1 || exit 0
notify-send -e -a hearth-deploy -i software-update-available -- \
  "$summary" "$body" >/dev/null 2>&1 || true
EOS
}

open_ssh() {
  ensure_ssh_include
  exec ssh "${SSH_OPTS[@]}" "$TARGET"
}

new_log() {
  local action="$1"
  TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
  LOG_FILE="$LOG_DIR/hearth-${action}-${TIMESTAMP}.log"
}

interactive_loop() {
  run_doctor || true
  while true; do
    printf '\n'
    render_status
    local choice
    choice="$(choose_action)"
    case "$choice" in
      Build)
        new_log build
        run_build || true
        ;;
      Dry-activate)
        new_log dry-activate
        run_deploy dry-activate || true
        ;;
      Switch)
        new_log switch
        run_deploy switch || true
        run_doctor || true
        ;;
      Boot)
        new_log boot
        run_deploy boot || true
        ;;
      Health)
        run_doctor || true
        run_healthcheck || true
        ;;
      Recheck)
        run_doctor || true
        ;;
      SSH)
        open_ssh
        ;;
      Quit)
        return 0
        ;;
      *)
        warn "Unknown action"
        ;;
    esac
  done
}

main() {
  local action="tui"
  NO_PROMPT="${HEARTH_DEPLOY_NO_PROMPT:-0}"
  STAGE=1
  FROM_CHECKOUT=0
  SWITCH_SOURCE="pin"
  NIXOS_DIR="${NIXOS_DIR:-$HOME/.config/nixos}"
  LOG_DIR="${HEARTH_DEPLOY_LOG_DIR:-$HOME/.cache/hearth-deploy}"

  while (($#)); do
    case "$1" in
      status | doctor | health | build | dry-activate | switch | boot | ssh)
        action="$1"
        ;;
      --yes)
        NO_PROMPT=1
        ;;
      --no-stage)
        STAGE=0
        ;;
      --from-checkout)
        FROM_CHECKOUT=1
        ;;
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

  NIXOS_DIR="$(cd "$NIXOS_DIR" 2>/dev/null && pwd -P)" || {
    error "NixOS directory does not exist: ${NIXOS_DIR:-<unset>}"
    return 2
  }
  export NIXOS_DIR
  FLAKE="${NIXOS_DIR}#${FLAKE_OUTPUT}"
  mkdir -p "$LOG_DIR"

  [[ -f "$NIXOS_DIR/flake.nix" ]] || {
    error "flake.nix not found under $NIXOS_DIR"
    return 2
  }
  command_exists nix || {
    error "nix is not available"
    return 2
  }
  if [[ "$action" != "tui" && "$action" != "status" && "$action" != "doctor" && "$action" != "health" && "$action" != "ssh" ]]; then
    command_exists nixos-rebuild || {
      error "nixos-rebuild is not available"
      return 2
    }
  fi

  setup_ssh

  case "$action" in
    tui)
      refuse_if_on_hearth
      interactive_loop
      ;;
    status)
      refuse_if_on_hearth
      run_doctor || true
      print_status_report
      ;;
    doctor)
      refuse_if_on_hearth
      run_doctor || true
      print_status_report
      ;;
    health)
      refuse_if_on_hearth
      run_doctor || true
      run_healthcheck
      ;;
    build)
      refuse_if_on_hearth
      new_log build
      run_build
      ;;
    dry-activate | switch | boot)
      refuse_if_on_hearth
      new_log "$action"
      run_doctor || true
      run_deploy "$action"
      ;;
    ssh)
      open_ssh
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi

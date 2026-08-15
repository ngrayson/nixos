#!/usr/bin/env bash
set -euo pipefail

# Guided, flake-native NixOS rebuild helper.

info() { printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[err]\033[0m  %s\n" "$*" >&2; }
ok() { printf "\033[1;32m[ok]\033[0m   %s\n" "$*"; }
heading() { printf "\n\033[1m%s\033[0m\n" "$*"; }

usage() {
  cat <<'EOF'
Guided, flake-native NixOS rebuild helper.

Usage:
  os-rebuild [explain|check|build|dry-activate|test|switch|boot] [options]

Actions:
  explain       Show which configuration scopes have changed; do not evaluate
  check         Validate the flake and selected host; do not build
  build         Build the selected host without activating it
  dry-activate  Build and show activation changes
  test          Activate until the next reboot
  switch        Activate now and make the generation the boot default
  boot          Build and make the generation the next boot default

Options:
  --host HOST             Named nixosConfigurations output (default: hostname)
  --edit[=SCOPE]          Open a guided target, or one of:
                          base, flake, host, hardware, home
  --format                Run the flake formatter before validation
  --yes                   Skip the rebuild confirmation
  --allow-host-mismatch   Permit activation for a host other than this machine
  --commit                After success, commit dirty changes (default)
  --no-commit             Do not commit after a successful rebuild
  -h, --help              Show this help

Environment:
  NIXOS_DIR               Flake directory (default: ~/.config/nixos)
  NIXOS_HOST              Named host output (default: hostname)
  OS_REBUILD_LOG_DIR      Log directory (default: ~/.cache/os-rebuild)
  OS_REBUILD_NO_PROMPT=1  Equivalent to --yes

Examples:
  os-rebuild explain --host Tawa
  os-rebuild check --host Tawa
  os-rebuild build --host Tawa
  os-rebuild dry-activate --host Tawa
  os-rebuild switch --host Tawa
  os-rebuild boot --host Theseus
  os-rebuild --edit=hardware --host Theseus build
EOF
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

prompt_confirm() {
  local question="$1"
  local default="${2:-no}"
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

is_activation_action() {
  case "$1" in
    dry-activate | test | switch | boot) return 0 ;;
    *) return 1 ;;
  esac
}

classify_path() {
  local path="$1"
  local host="${NIXOS_HOST:-$(hostname)}"

  case "$path" in
    flake.nix | flake.lock)
      printf '%s\n' "flake"
      ;;
    common/base.nix | common/system.nix | common/* | profiles/*)
      printf '%s\n' "base"
      ;;
    home.nix | home/* | desktop/* | fastfetch/* | kitty/* | kvantum/*)
      printf '%s\n' "home"
      ;;
    "hosts/$host/hardware-configuration.nix" | "hosts/$host/disko.nix")
      printf '%s\n' "hardware"
      ;;
    "hosts/$host/"*)
      printf '%s\n' "host"
      ;;
    hosts/*)
      printf '%s\n' "other-host"
      ;;
    documentation/* | scripts/* | .cursor/* | *.md)
      printf '%s\n' "tooling"
      ;;
    configuration.nix)
      printf '%s\n' "legacy"
      ;;
    *)
      printf '%s\n' "other"
      ;;
  esac
}

append_scope_file() {
  local category="$1"
  local path="$2"

  case "$category" in
    flake) SCOPE_FLAKE+=("$path") ;;
    base) SCOPE_BASE+=("$path") ;;
    home) SCOPE_HOME+=("$path") ;;
    hardware) SCOPE_HARDWARE+=("$path") ;;
    host) SCOPE_HOST+=("$path") ;;
    other-host) SCOPE_OTHER_HOST+=("$path") ;;
    tooling) SCOPE_TOOLING+=("$path") ;;
    legacy) SCOPE_LEGACY+=("$path") ;;
    other) SCOPE_OTHER+=("$path") ;;
  esac
}

print_scope_group() {
  local title="$1"
  local explanation="$2"
  shift 2
  local files=("$@")

  ((${#files[@]})) || return 0
  printf "\n  \033[1m%s\033[0m — %s\n" "$title" "$explanation"
  printf '    - %s\n' "${files[@]}"
}

collect_change_scope() {
  SCOPE_FLAKE=()
  SCOPE_BASE=()
  SCOPE_HOME=()
  SCOPE_HARDWARE=()
  SCOPE_HOST=()
  SCOPE_OTHER_HOST=()
  SCOPE_TOOLING=()
  SCOPE_LEGACY=()
  SCOPE_OTHER=()
  HAS_UNTRACKED=0
  UNTRACKED_FLAKE_INPUTS=()

  command_exists git || return 0
  git -C "$NIXOS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local line status path category
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    status="${line:0:2}"
    path="${line:3}"
    if [[ "$path" == *" -> "* ]]; then
      path="${path##* -> }"
    fi
    category="$(classify_path "$path")"
    if [[ "$status" == "??" ]]; then
      HAS_UNTRACKED=1
      case "$category" in
        tooling | legacy) ;;
        *) UNTRACKED_FLAKE_INPUTS+=("$path") ;;
      esac
    fi
    append_scope_file "$category" "$path"
  done < <(git -C "$NIXOS_DIR" status --porcelain=v1 --untracked-files=all)
}

show_change_scope() {
  heading "Configuration scope"

  local total
  total=$((
    ${#SCOPE_FLAKE[@]}
      + ${#SCOPE_BASE[@]}
      + ${#SCOPE_HOME[@]}
      + ${#SCOPE_HARDWARE[@]}
      + ${#SCOPE_HOST[@]}
      + ${#SCOPE_OTHER_HOST[@]}
      + ${#SCOPE_TOOLING[@]}
      + ${#SCOPE_LEGACY[@]}
      + ${#SCOPE_OTHER[@]}
  ))

  if ((total == 0)); then
    printf "  Working tree is clean. The build uses the committed flake revision.\n"
    return 0
  fi

  print_scope_group \
    "FLAKE / INPUTS" \
    "host graph or pinned dependencies; can affect every output" \
    "${SCOPE_FLAKE[@]}"
  print_scope_group \
    "SHARED BASE" \
    "shared NixOS/profile settings; can affect multiple hosts" \
    "${SCOPE_BASE[@]}"
  print_scope_group \
    "HOME / DESKTOP" \
    "Home Manager and desktop state for workstation users" \
    "${SCOPE_HOME[@]}"
  print_scope_group \
    "HARDWARE: $NIXOS_HOST" \
    "disk, filesystem, initrd, or device settings; review before activation" \
    "${SCOPE_HARDWARE[@]}"
  print_scope_group \
    "HOST: $NIXOS_HOST" \
    "machine-specific settings for the selected output" \
    "${SCOPE_HOST[@]}"
  print_scope_group \
    "OTHER HOST" \
    "normally does not affect $NIXOS_HOST unless flake imports link them" \
    "${SCOPE_OTHER_HOST[@]}"
  print_scope_group \
    "DOCS / TOOLING" \
    "does not normally change the built NixOS closure" \
    "${SCOPE_TOOLING[@]}"
  print_scope_group \
    "LEGACY ENTRYPOINT" \
    "configuration.nix is not used by named flake outputs" \
    "${SCOPE_LEGACY[@]}"
  print_scope_group \
    "OTHER / ASSET" \
    "effect depends on whether a Nix module references the path" \
    "${SCOPE_OTHER[@]}"

  if ((HAS_UNTRACKED)); then
    warn "Untracked files exist. Git-backed flakes omit them until they are staged."
  fi

  if ((${#UNTRACKED_FLAKE_INPUTS[@]})); then
    warn "These untracked paths may be configuration inputs:"
    printf '    - %s\n' "${UNTRACKED_FLAKE_INPUTS[@]}"
  fi
}

repo_is_dirty() {
  command_exists git || return 1
  git -C "$NIXOS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [[ -n "$(git -C "$NIXOS_DIR" status --porcelain)" ]]
}

show_repository_diff() {
  repo_is_dirty || return 0

  heading "Repository diff"
  git -C "$NIXOS_DIR" --no-pager status --short
  printf "\n"
  git -C "$NIXOS_DIR" --no-pager diff --stat HEAD
  printf "\n"
  # Staged + unstaged content vs HEAD. Nix git flakes include dirty *tracked*
  # files in the build; untracked files are omitted until `git add`.
  git -C "$NIXOS_DIR" --no-pager diff HEAD
  if [[ -n "$(git -C "$NIXOS_DIR" ls-files --others --exclude-standard)" ]]; then
    printf "\n"
    warn "Untracked files are shown above but are NOT in the flake build until staged."
  fi

  heading "Build vs commit"
  printf "  - Tracked dirty files in the diff ARE included in this rebuild (dirty git flake).\n"
  printf "  - After a successful rebuild, dirty changes are committed by default.\n"
  printf "  - Pass --no-commit to leave the working tree dirty.\n"
}

show_guidance() {
  heading "Guidance"

  if ((${#SCOPE_HARDWARE[@]})); then
    warn "Hardware configuration changed."
    printf "  - Confirm UUIDs and LUKS/swap mappings against the selected machine.\n"
    printf "  - Prefer 'build', then 'dry-activate', then 'boot'.\n"
    printf "  - Keep a known-good boot generation available.\n"
  fi

  if ((${#SCOPE_FLAKE[@]})); then
    printf "  - Flake changes may alter package versions, modules, or host wiring.\n"
    printf "  - Review flake.lock changes and run 'check' before activation.\n"
  fi

  if ((${#SCOPE_BASE[@]})); then
    printf "  - Shared-base changes may affect hosts beyond %s.\n" "$NIXOS_HOST"
  fi

  if ((${#SCOPE_HOME[@]})); then
    printf "  - Home changes activate through the NixOS Home Manager service.\n"
  fi

  if ((${#SCOPE_OTHER_HOST[@]})); then
    printf "  - Changes under other hosts are shown for awareness but are not the selected target.\n"
  fi

  if ((${#SCOPE_LEGACY[@]})); then
    warn "The legacy root configuration changed, but --flake #$NIXOS_HOST does not import it."
  fi

  if is_activation_action "$ACTION" && ((${#SCOPE_HARDWARE[@]})) && [[ "$ACTION" != "boot" ]]; then
    warn "Selected action '$ACTION' is not the safest hardware-change workflow; consider 'boot'."
  fi
}

select_edit_file() {
  local scope="$1"
  local reply

  if [[ "$scope" == "guided" ]]; then
    [[ -t 0 ]] || {
      error "--edit needs an interactive terminal; use --edit=SCOPE"
      return 2
    }
    cat <<EOF

What do you want to edit?
  1) shared base     common/system.nix
  2) flake wiring   flake.nix
  3) host settings  hosts/$NIXOS_HOST/host.nix
  4) hardware       hosts/$NIXOS_HOST/hardware-configuration.nix
  5) home/desktop   home/default.nix
EOF
    printf "Choose 1-5: "
    read -r reply
    case "$reply" in
      1) scope="base" ;;
      2) scope="flake" ;;
      3) scope="host" ;;
      4) scope="hardware" ;;
      5) scope="home" ;;
      *)
        error "Invalid edit choice"
        return 2
        ;;
    esac
  fi

  case "$scope" in
    base) EDIT_FILE="$NIXOS_DIR/common/system.nix" ;;
    flake) EDIT_FILE="$NIXOS_DIR/flake.nix" ;;
    host) EDIT_FILE="$NIXOS_DIR/hosts/$NIXOS_HOST/host.nix" ;;
    hardware) EDIT_FILE="$NIXOS_DIR/hosts/$NIXOS_HOST/hardware-configuration.nix" ;;
    home) EDIT_FILE="$NIXOS_DIR/home/default.nix" ;;
    *)
      error "Unknown edit scope '$scope' (use base, flake, host, hardware, or home)"
      return 2
      ;;
  esac

  [[ -f "$EDIT_FILE" ]] || {
    error "Edit target does not exist: $EDIT_FILE"
    return 2
  }
}

check_placeholder_hardware() {
  local hardware="$NIXOS_DIR/hosts/$NIXOS_HOST/hardware-configuration.nix"

  [[ -f "$hardware" ]] || return 0
  if grep -q '00000000-0000-4000-8000-00000000000' "$hardware"; then
    if is_activation_action "$ACTION"; then
      error "$hardware still contains placeholder UUIDs."
      error "Refusing to activate a non-deployable hardware configuration."
      return 1
    fi
    warn "$hardware contains placeholder UUIDs; build-only validation is allowed."
  fi
}

check_untracked_flake_inputs() {
  ((${#UNTRACKED_FLAKE_INPUTS[@]} == 0)) && return 0

  error "Refusing to build while configuration inputs are untracked."
  error "A Git flake cannot see them. Review and stage the intended files, for example:"
  printf '  git -C %q add' "$NIXOS_DIR" >&2
  printf ' %q' "${UNTRACKED_FLAKE_INPUTS[@]}" >&2
  printf '\n' >&2
  return 1
}

run_logged() {
  local -a command=("$@")
  local rc

  set +e
  "${command[@]}" 2>&1 | tee "$LOG_FILE"
  rc=${PIPESTATUS[0]}
  set -e
  return "$rc"
}

main() {
  ACTION="switch"
  NIXOS_DIR="${NIXOS_DIR:-$HOME/.config/nixos}"
  NIXOS_HOST="${NIXOS_HOST:-$(hostname)}"
  LOG_DIR="${OS_REBUILD_LOG_DIR:-$HOME/.cache/os-rebuild}"
  NO_PROMPT="${OS_REBUILD_NO_PROMPT:-0}"
  EDIT_SCOPE=""
  FORMAT=0
  COMMIT=1
  ALLOW_HOST_MISMATCH=0

  while (($#)); do
    case "$1" in
      explain | check | build | dry-activate | test | switch | boot)
        ACTION="$1"
        ;;
      --host)
        shift
        NIXOS_HOST="${1:-}"
        [[ -n "$NIXOS_HOST" ]] || {
          error "--host requires a value"
          return 2
        }
        ;;
      --edit)
        EDIT_SCOPE="guided"
        ;;
      --edit=*)
        EDIT_SCOPE="${1#--edit=}"
        ;;
      --format)
        FORMAT=1
        ;;
      --yes)
        NO_PROMPT=1
        ;;
      --allow-host-mismatch)
        ALLOW_HOST_MISMATCH=1
        ;;
      --commit)
        COMMIT=1
        ;;
      --no-commit)
        COMMIT=0
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
  # Keep this Git-backed: unlike path:, it cannot accidentally copy ignored
  # secrets into the world-readable Nix store. Untracked inputs are blocked.
  FLAKE_ROOT="$NIXOS_DIR"
  FLAKE="$FLAKE_ROOT#$NIXOS_HOST"
  TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
  LOG_FILE="$LOG_DIR/nixos-rebuild-${NIXOS_HOST}-${ACTION}-${TIMESTAMP}.log"

  [[ -f "$NIXOS_DIR/flake.nix" ]] || {
    error "flake.nix not found under $NIXOS_DIR"
    return 2
  }
  command_exists nix || {
    error "nix is not available"
    return 2
  }
  if [[ "$ACTION" != "explain" && "$ACTION" != "check" ]]; then
    command_exists nixos-rebuild || {
      error "nixos-rebuild is not available"
      return 2
    }
  fi

  if [[ -n "$EDIT_SCOPE" ]]; then
    [[ -n "${EDITOR:-}" ]] || {
      error "\$EDITOR is not set"
      return 2
    }
    select_edit_file "$EDIT_SCOPE"
    info "Editing ${EDIT_FILE#"$NIXOS_DIR/"}"
    "$EDITOR" "$EDIT_FILE"
  fi

  if ((FORMAT)); then
    info "Formatting flake sources"
    nix fmt "$FLAKE_ROOT"
  fi

  collect_change_scope

  heading "Target"
  printf "  action:      %s\n" "$ACTION"
  printf "  host output: nixosConfigurations.%s\n" "$NIXOS_HOST"
  printf "  flake:       %s\n" "$FLAKE_ROOT"
  if [[ "$ACTION" != "explain" && "$ACTION" != "check" ]]; then
    printf "  log:         %s\n" "$LOG_FILE"
  fi

  show_change_scope
  show_repository_diff
  show_guidance

  if [[ "$ACTION" == "explain" ]]; then
    return 0
  fi

  check_untracked_flake_inputs

  info "Validating all tracked/staged flake outputs"
  nix flake check --no-build "$FLAKE_ROOT"

  local configured_host
  configured_host="$(
    nix eval --raw \
      "$FLAKE_ROOT#nixosConfigurations.${NIXOS_HOST}.config.networking.hostName"
  )" || {
    error "No valid nixosConfigurations.$NIXOS_HOST output was found."
    return 1
  }
  ok "Selected output evaluates with networking.hostName=$configured_host"

  check_placeholder_hardware

  local current_host
  current_host="$(hostname)"
  if is_activation_action "$ACTION" && [[ "$configured_host" != "$current_host" ]]; then
    if ((ALLOW_HOST_MISMATCH == 0)); then
      error "Refusing to '$ACTION' $configured_host while running on $current_host."
      error "Use 'build' for another host, or pass --allow-host-mismatch deliberately."
      return 1
    fi
    warn "Host mismatch explicitly allowed: $current_host -> $configured_host"
  fi

  if [[ "$ACTION" == "check" ]]; then
    ok "Flake and host validation succeeded"
    return 0
  fi

  mkdir -p "$LOG_DIR"

  local default_answer="yes"
  is_activation_action "$ACTION" && default_answer="no"
  if [[ "$NO_PROMPT" != "1" ]] &&
    ! prompt_confirm "Run '$ACTION' for $configured_host?" "$default_answer"; then
    warn "Aborted"
    return 0
  fi

  local -a rebuild=(nixos-rebuild "$ACTION" --flake "$FLAKE")
  if [[ "$ACTION" != "build" ]]; then
    rebuild=(sudo "${rebuild[@]}")
  fi

  info "Running: ${rebuild[*]}"
  local rc
  if run_logged "${rebuild[@]}"; then
    rc=0
  else
    rc=$?
    error "nixos-rebuild $ACTION failed (exit $rc)"
    warn "Full log: $LOG_FILE"
    command_exists notify-send &&
      notify-send -e "NixOS rebuild FAILED" "See $LOG_FILE" \
        --icon=software-update-urgent 2>/dev/null || true
    return "$rc"
  fi

  ok "nixos-rebuild $ACTION succeeded"

  case "$ACTION" in
    build)
      printf "  Next safe step: os-rebuild dry-activate --host %s\n" "$NIXOS_HOST"
      ;;
    dry-activate)
      printf "  Review the output, then choose switch or boot explicitly.\n"
      ;;
    test)
      printf "  Active for this boot only; reboot restores the boot-default generation.\n"
      ;;
    boot)
      printf "  Installed as the next boot generation; this helper will not reboot automatically.\n"
      ;;
    switch)
      printf "  Active now and selected as the boot-default generation.\n"
      ;;
  esac

  if repo_is_dirty; then
    if ((COMMIT == 0)); then
      info "Leaving working tree dirty (--no-commit)."
    else
      warn "Working tree is dirty after the rebuild; committing records what was just built."
      printf "  This stages every repository change, including unrelated files.\n"
      local do_commit=0
      if [[ "$NO_PROMPT" == "1" ]]; then
        do_commit=1
      elif prompt_confirm "Commit all current repository changes?" "yes"; then
        do_commit=1
      fi
      if ((do_commit)); then
        git -C "$NIXOS_DIR" add -A
        git -C "$NIXOS_DIR" commit -m "NixOS $NIXOS_HOST $ACTION"
        ok "Committed repository changes"
      else
        info "Skipped commit; pass --no-commit next time to silence this prompt."
      fi
    fi
  fi

  command_exists notify-send &&
    notify-send -e "NixOS $ACTION OK" "$NIXOS_HOST" \
      --icon=software-update-available 2>/dev/null || true
  ok "Log saved at $LOG_FILE"
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi

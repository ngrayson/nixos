#!/usr/bin/env bash
# Launch Rally Cry Conveyor MCP with credentials from ~/.config/conveyor/env.
# Mint a token from Conveyor → Settings → User Settings → Connect Claude Code.
set -euo pipefail

env_file="${CONVEYOR_ENV_FILE:-${HOME}/.config/conveyor/env}"
if [[ -f "${env_file}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
fi

if [[ -z "${CONVEYOR_API_URL:-}" || -z "${CONVEYOR_USER_TOKEN:-}${CONVEYOR_PROJECT_TOKEN:-}" ]]; then
  echo "conveyor-mcp: missing CONVEYOR_API_URL and CONVEYOR_USER_TOKEN." >&2
  echo "Create ${env_file} (see ${HOME}/.config/conveyor/env.example)." >&2
  echo "Source: Conveyor project → Settings → User Settings → Connect Claude Code." >&2
  exit 1
fi

if [[ -x "${HOME}/.local/bin/conveyor-mcp" ]]; then
  exec "${HOME}/.local/bin/conveyor-mcp" "$@"
fi
exec /run/current-system/sw/bin/npx -y @rallycry/conveyor-mcp@latest "$@"

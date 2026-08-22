#!/usr/bin/env bash
set -euo pipefail

# Codespace / Conveyor Claudespace only. Local NixOS work uses os-rebuild
# on the host — never this script.
if [ "${CODESPACES:-}" != "true" ] && [ -z "${REMOTE_CONTAINERS:-}" ] && [ ! -f /.dockerenv ]; then
  echo "setup.sh: not a codespace/devcontainer context — refusing." >&2
  exit 0
fi

echo "[conveyor] WizOs codespace setup"
if command -v nix >/dev/null 2>&1; then
  echo "[conveyor] $(nix --version)"
  # Eval-only. Never nixos-rebuild / os-rebuild switch in a codespace.
  echo "[conveyor] nix flake check (hostname evals, not toplevel)"
  nix flake check --no-build
else
  echo "[conveyor] nix not on PATH yet (the nix feature may still be installing)"
fi

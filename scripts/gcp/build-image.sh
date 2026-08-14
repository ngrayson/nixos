#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
out_link="${1:-$repo/result-gcp}"

exec nix build \
  "$repo#nixosConfigurations.Gcp.config.system.build.googleComputeImage" \
  --out-link "$out_link"

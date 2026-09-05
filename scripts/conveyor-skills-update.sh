#!/usr/bin/env bash
# Bump the pinned @rallycry/conveyor-skills version + hash in
# home/programs/claude-skills.nix to the latest npm release, then remind to
# activate. `--check` compares against npm and prints the result without editing.
#
# After a bump: os-rebuild switch (the new ~/.claude/skills tree lands on
# activation; a running session needs a CLI restart to see new skills).
set -euo pipefail

NIXOS_DIR="${NIXOS_DIR:-$HOME/.config/nixos}"
module="$NIXOS_DIR/home/programs/claude-skills.nix"
pkg="@rallycry/conveyor-skills"

check_only=0
case "${1:-}" in
  --check) check_only=1 ;;
  "") ;;
  *)
    echo "usage: conveyor-skills-update [--check]" >&2
    exit 2
    ;;
esac

[[ -f "$module" ]] || {
  echo "conveyor-skills-update: not found: $module" >&2
  exit 1
}

current="$(sed -n 's/^[[:space:]]*version = "\(.*\)";/\1/p' "$module" | head -1)"
[[ -n "$current" ]] || {
  echo "conveyor-skills-update: could not read the pinned version from $module" >&2
  exit 1
}

latest="$(npm view "$pkg" version)"
[[ -n "$latest" ]] || {
  echo "conveyor-skills-update: could not query npm for $pkg" >&2
  exit 1
}

if [[ "$current" == "$latest" ]]; then
  echo "already at $current"
  exit 0
fi

echo "$current -> $latest"
(( check_only )) && exit 0

url="https://registry.npmjs.org/$pkg/-/conveyor-skills-$latest.tgz"
hash="$(nix hash convert --hash-algo sha256 --to sri "$(nix-prefetch-url --unpack "$url")")"
[[ -n "$hash" ]] || {
  echo "conveyor-skills-update: could not compute the tarball hash" >&2
  exit 1
}

# Rewrite exactly the two pinned lines in place.
sed -i \
  -e "s|^\([[:space:]]*version = \"\)[^\"]*\(\";\)|\1${latest}\2|" \
  -e "s|^\([[:space:]]*hash = \"\)[^\"]*\(\";\)|\1${hash}\2|" \
  "$module"

echo "bumped $current -> $latest; run os-rebuild switch"

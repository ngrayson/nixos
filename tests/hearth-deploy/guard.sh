#!/bin/sh
# Tests refuse_shared_deploy_paths (scripts/hearth-deploy.sh) against a scratch
# git repo with a bare origin. Run with bash; flake check: hearth-deploy-guard-tests.
#   bash tests/hearth-deploy/guard.sh <path/to/hearth-deploy.sh> <scratch-dir>
# Exits non-zero if any case gives the wrong answer.
script=$1; t=$2
mkdir -p "$t"
# hearth-deploy.sh has a source guard, so this defines its functions without running main.
. "$script"
set +e +u
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
g() { git -C "$NIXOS_DIR" -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@" >/dev/null 2>&1; }
new() {
  rm -rf "$t/bare" "$t/r"; git init -q --bare -b main "$t/bare"; git init -q -b main "$t/r"
  NIXOS_DIR="$t/r"
  mkdir -p "$t/r/common" "$t/r/hosts/Hearth"; echo a > "$t/r/common/x.nix"; echo a > "$t/r/hosts/Hearth/y.nix"
  g add -A; g commit -m init; g remote add origin "$t/bare"; g push origin main; g fetch origin
  unset HEARTH_DEPLOY_ALLOW_SHARED
}
fails=0
check() {
  refuse_shared_deploy_paths HEAD >/dev/null 2>&1; got=$?
  if [ "$1" = "$got" ]; then r=PASS; else r=FAIL; fails=$((fails + 1)); fi
  printf '  [%s] %-44s want=%s got=%s\n' "$r" "$2" "$1" "$got"
}
FROM_CHECKOUT=0
new; echo b >> "$t/r/hosts/Hearth/y.nix"; g commit -am hearth;  check 0 "committed hosts/Hearth only"
new; echo b >> "$t/r/common/x.nix"; g commit -am common;        check 1 "committed common/ change"
new; echo b >> "$t/r/common/x.nix"; g commit -am "common

Hearth-Deploy: allow-shared";                                   check 0 "committed common/ with trailer"
new; echo b >> "$t/r/common/x.nix"; FROM_CHECKOUT=0;            check 0 "uncommitted common/, pin deploy"
FROM_CHECKOUT=1;                                                check 1 "uncommitted common/, --from-checkout"
new; echo n > "$t/r/common/new.nix"; FROM_CHECKOUT=1;           check 1 "untracked common/new.nix, --from-checkout"
new; echo b >> "$t/r/hosts/Hearth/y.nix"; FROM_CHECKOUT=1;      check 0 "uncommitted hosts/Hearth, --from-checkout"
new; g remote remove origin; g update-ref -d refs/remotes/origin/main; FROM_CHECKOUT=0; check 1 "no origin/main at all"
new; echo b >> "$t/r/common/x.nix"; FROM_CHECKOUT=1; HEARTH_DEPLOY_ALLOW_SHARED=1; check 0 "uncommitted common/ with env override"
[ "$fails" -eq 0 ] && echo "hearth-deploy-guard-tests: ALL PASS" || echo "hearth-deploy-guard-tests: $fails FAILED"
exit "$fails"

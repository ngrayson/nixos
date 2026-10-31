#!/usr/bin/env bash
# Read-only sweep for the backdoored anthropic.claude-code 2.1.313 extension
# (phorion.io advisory, 2026-10-30). Exit 0 only when no indicator is found.
# Prints counts, basenames and ok/fail only, never key or file contents.
# Intended: ssh hearth sudo bash -s < scripts/ioc-sweep-claude-vsx.sh; echo "exit=$?"
# As root it sweeps /root and /home/*; otherwise only $HOME (no journal).
set -euo pipefail
shopt -s nullglob

BAD_SHA=ecb58cb29078d9646ad1dcdbe51526f2d9cfea06be5fb2ab183e8ecc3ab6bf15
BAD_FPS='0Z6R\+DF64Do2nwQic8a7kkfDLNNk4IiK\+2U2Rci4htk|KOAU57\+ZG6u3MG4WwzPzPX2O5YEe9qdOC1Bl\+6MVyDQ'
C2=134.209.82.225
failed=0

ok() { printf '[ok]   %s\n' "$*"; }
fail() { printf '[fail] %s\n' "$*" >&2; failed=1; }

if [[ $EUID -eq 0 ]]; then
  homes=(/root /home/*)
else
  homes=("$HOME")
  ok "not root: sweeping $HOME only; other users and the journal are skipped"
fi

for h in "${homes[@]}"; do
  [[ -d $h ]] || continue
  for d in "$h"/.vscode/extensions/anthropic.claude-code-* \
           "$h"/.vscode-oss/extensions/anthropic.claude-code-* \
           "$h"/.cursor/extensions/anthropic.claude-code-* \
           "$h"/.windsurf/extensions/anthropic.claude-code-*; do
    b="${d##*/}"
    if [[ $b == anthropic.claude-code-2.1.313* ]]; then
      fail "$h: backdoored extension dir $b"
    else
      ok "$h: extension $b"
    fi
    f="$d/extension.js"
    [[ -f $f ]] || continue
    if [[ "$(sha256sum "$f" | cut -d' ' -f1)" == "$BAD_SHA" ]]; then
      fail "$h: $b/extension.js matches the advisory sha256"
    fi
    # The hash may be of the VSIX, so also look for the strings themselves.
    if grep -q -E "svc-telemetry|$C2" "$f"; then
      fail "$h: $b/extension.js contains an IOC string"
    fi
  done

  ak="$h/.ssh/authorized_keys"
  if [[ -f $ak ]]; then
    if grep -q 'svc-telemetry' "$ak"; then
      fail "$h: authorized_keys has a svc-telemetry entry"
    elif ! command -v ssh-keygen >/dev/null 2>&1; then
      fail "$h: ssh-keygen missing, cannot check key fingerprints"
    elif fps="$(ssh-keygen -lf "$ak" 2>/dev/null || true)"; grep -q -E "$BAD_FPS" <<<"$fps"; then
      fail "$h: authorized_keys has an advisory key fingerprint"
    else
      ok "$h: authorized_keys $(wc -l < "$ak") line(s), no IOC"
    fi
  else
    ok "$h: no authorized_keys"
  fi

  for p in "$h/.config/.smt" "$h/.config/.smtk"; do
    if [[ -e $p ]]; then fail "$h: persistence file ${p##*/} exists"; fi
  done

  if command -v crontab >/dev/null 2>&1; then
    tab="$(crontab -u "$(stat -c %U "$h")" -l 2>/dev/null || true)"
    if grep -q '\.smt' <<<"$tab"; then
      fail "$h: crontab references .smt"
    fi
  fi
done
command -v crontab >/dev/null 2>&1 || ok "crontab not installed"

stk=(/tmp/.stk_*)
if ((${#stk[@]})); then fail "${#stk[@]} /tmp/.stk_* file(s)"; else ok "no /tmp/.stk_*"; fi

if pgrep -f -a "autossh|ssh .*-R \*:0:localhost:22|$C2" >/dev/null; then
  fail "process matching a tunnel indicator"
else
  ok "no tunnel process"
fi

conns="$(ss -tn 2>/dev/null || true)"
if grep -q "$C2" <<<"$conns"; then
  fail "connection to $C2"
else
  ok "no connection to $C2"
fi

if [[ $EUID -eq 0 ]] && command -v journalctl >/dev/null 2>&1; then
  acc="$(journalctl -u sshd --since 2026-10-01 --no-pager 2>/dev/null | grep -E 'Accepted ' || true)"
  if grep -q -E 'from (127\.0\.0\.1|::1) ' <<<"$acc"; then
    fail "sshd accepted a login from loopback"
  else
    ok "sshd accepted $(grep -c . <<<"$acc") login(s) since 2026-10-01, none from loopback"
  fi
fi

printf '%s: %s\n' "$(hostname)" "$([[ $failed -eq 0 ]] && echo clean || echo 'INDICATORS FOUND')"
exit "$failed"

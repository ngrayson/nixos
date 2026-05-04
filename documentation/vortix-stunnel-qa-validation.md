# QA Manual Validation Criteria: Vortix + Stunnel

Use this checklist after deploying changes to the declarative VPN stack.

## Scope

Validate:

- Declarative installation of `vortix`
- `stunnel` client wiring for FrootVPN
- Shell/desktop entrypoints (`vpn`, `vpn-froot`, desktop launcher)
- Stunnel-backed profile behavior

## Test environment prerequisites

- System rebuilt with latest config:
  - `sudo nixos-rebuild switch`
- Tester account has sudo access.
- At least one stunnel-backed `.ovpn` profile is available in `~/.config/ovpn`.
- External network access is available.

## Pass/fail rules

- A test **passes** only when expected result is observed exactly.
- A test **fails** on any mismatch, command error, missing binary/service, or unexpected prompt.
- Record:
  - Hostname
  - Build generation ID
  - Test case ID
  - Result (Pass/Fail)
  - Notes/screenshots/error output

## Test cases

### QA-VPN-001: Vortix binary is declaratively available

**Steps**

1. Run: `command -v vortix`
2. Run: `vortix --version`

**Expected**

- `command -v` returns a valid path.
- `vortix --version` prints version info and exits 0.

---

### QA-VPN-002: Stunnel service is active and listening

**Steps**

1. Run: `systemctl status stunnel.service --no-pager`
2. Run: `ss -ltnp | rg 1194`

**Expected**

- `stunnel.service` state is `active (running)`.
- Listener appears on `127.0.0.1:1194`.

---

### QA-VPN-003: CA file is correctly deployed

**Steps**

1. Run: `ls -l /etc/frootvpn/stunnel-ca.pem`
2. Run: `sudo openssl x509 -in /etc/frootvpn/stunnel-ca.pem -noout -subject -issuer -dates`

**Expected**

- File exists and is readable.
- Certificate metadata is printed without parse errors.

---

### QA-VPN-004: Shell aliases resolve correctly

**Steps**

1. Run: `alias vpn`
2. Run: `alias vpn-froot`

**Expected**

- `vpn` resolves to `sudo vortix`.
- `vpn-froot` resolves to `vpn-froot` wrapper command.

---

### QA-VPN-005: `vpn-froot` guard blocks when stunnel is down

**Steps**

1. Stop service: `sudo systemctl stop stunnel.service`
2. Run: `vpn-froot`

**Expected**

- Command exits non-zero.
- User sees a clear message that `stunnel.service` is not active.
- `vortix` UI does **not** launch.

**Cleanup**

- Restart service: `sudo systemctl start stunnel.service`

---

### QA-VPN-006: `vpn-froot` launches when stunnel is healthy

**Steps**

1. Ensure service is active: `systemctl is-active stunnel.service`
2. Run: `vpn-froot`
3. If prompted, authenticate with sudo.

**Expected**

- Vortix launches successfully.
- No preflight error about stunnel inactivity.

---

### QA-VPN-007: Desktop launcher path matches shell path

**Steps**

1. Launch `VPN (Vortix)` from app menu.
2. Confirm it opens Kitty and starts the Vortix flow.

**Expected**

- Launcher works without manual command entry.
- Behavior matches `vpn-froot` path (same guard behavior if stunnel is down).

---

### QA-VPN-008: Stunnel-backed profile connect/disconnect

**Steps**

1. Open Vortix (via `vpn-froot`).
2. Select a profile configured for `127.0.0.1:1194`.
3. Connect.
4. Verify tunnel established in Vortix.
5. Disconnect.

**Expected**

- Connect succeeds without stunnel TLS errors.
- Disconnect succeeds cleanly.
- No stuck kill-switch/network state after disconnect.

## Regression checks

- Non-VPN shell behavior unaffected (`zsh` starts normally, aliases still load).
- Existing desktop entries still appear in app menu.
- Rebuild does not fail on VPN module evaluation.

## Sign-off criteria

A release is QA-approved when:

- All test cases QA-VPN-001 through QA-VPN-008 pass.
- Any transient network-related retries are documented.
- No unresolved critical or high-severity defects remain.

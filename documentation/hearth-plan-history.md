# Hearth plan — audit history

Historical detail moved out of [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md)
on 2026-08-31, when that file outgrew Conveyor's 32,000-character overview cap
for the `hearth` tag. Both sections below are **closed audit artifacts**: the
2026-08-21 reconciliation between the original "NixOS Home Server System
Canvas" and reality, and the risk register that came out of the same audit.
Every row is resolved or mitigated, and the live facts they resolved *to* are
in plan.md. Nothing here is an open action.

## Corrected context (2026-08-21)

The original canvas was written with incomplete context — wrong hardware, a
three-tier storage plan, and a pre-migration view of the machine.

| Item | Original plan said | Actual |
|------|--------------------|--------|
| Machine | Surface Pro 4 | **Surface Laptop 3** (i5-1035G7 Ice Lake, 8 GB RAM, 238 GB NVMe) |
| State | Greenfield | Already migrated to this flake as host `Hearth`; Jellyfin running and verified on LAN |
| Storage tiers | 3 (NVMe + 500 GB SSD + 2 TB HDD) | **2 (NVMe + HDD)** — no 500 GB SSD tier |
| Session | Assumed headless | Currently Hyprland desktop (from migration phase 2) — to be **converted to headless** (see H4) |
| Jellyfin | This node only | Tawa also serves Jellyfin today — **Tawa's will be disabled** (H3) |

## Risk register

| Audit risk | Status |
|------------|--------|
| Wrong hardware (Pro 4 vs Laptop 3) | **Resolved** — this doc is the corrected baseline |
| Role conflict (desktop vs headless) | **Resolved** — headless confirmed; H4 sequences the flip safely |
| Three-tier storage doesn't exist | **Resolved** — two-tier confirmed; HDD on hand (H2) |
| Media on NVMe | **Resolved** — H2 shipped; media is on `/mnt/cold` |
| Two Jellyfin servers | **Resolved** — Tawa's will be disabled (H3) |
| Docker creep | **Resolved** — NixOS modules only |
| Unsupervised switch on main | **Resolved** — push-based `hearth-deploy` from the `deploy/hearth` pin, plus H7 guardrails. comin cancelled (decision 21): it would bypass the path filter |
| On-box builds vs 8 GB RAM / small disk | **Mitigated** — space freed + headless RAM headroom; build-elsewhere preferred |
| No secrets story | **Resolved** — sops-nix + Bitwarden Pro vault confirmed (H5) |
| TV cannot run Tailscale | **Resolved** — TV + Hearth share GiGstreem (decision 13); wired LAN later |
| Jellyfin state migration | **Resolved** — fresh start (decision 14) |
| No remote SSH path | **Resolved** — H0 shipped; Tawa OpenSSH to GiGstreem `.38` proven 2026-08-22 |
| HDD on USB | **Mitigated** — powered UASP hub on USB-C, `nofail` mount, USB-A kept free for rescue |
| Battery-as-UPS vs suspend-on-battery | **Narrowed** — idle suspend ruled out (decision 17); only lid-close-on-battery policy left for H4 |

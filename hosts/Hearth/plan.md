# Hearth Home Server — Source of Truth

**v3 — 2026-09-01.** The navigation layer for Hearth: live facts, decisions,
phase status, open questions, and every binding rule (§8). Narrative, rationale
and measurements live in `documentation/`. When this file and older docs
disagree, this file wins.

**Adding here: a decision or a rule goes inline; its evidence goes into
`documentation/`.** This file is the `hearth` Conveyor tag's overview and is
silently truncated past 32,000 characters, so it is kept near 12,000. Do not
move, rename or retitle it — the tag pins the H1 line as its context locator —
and **never renumber** sections (1–8), decisions (1–21) or phases (H0–H8),
which `.nix` modules and `AGENTS.md` cite. Mark an obsolete decision
superseded in place rather than closing the gap.

---

## 1. Corrected context

Live facts (2026-08-21, post-H2): hostname `Hearth`, sshd key-only, Jellyfin
`Healthy`. **Wi-Fi is AncientGlade `192.168.0.133` during agent sessions**
(Cursor cannot reach this machine on GiGstreem). GiGstreem stays pinned at
**172.16.141.38/24** for TV hosting. Tailnet `hearth.tail6cd822.ts.net` =
`100.84.222.78`. The HDD is a Seagate IronWolf 4 TB NTFS volume `COLD` at
`/mnt/cold` (`media/` + `share/`); `/srv/media` emptied, unplug drill passed.

Reconciliation table and the audit's risk register:
[`hearth-plan-history.md`](../../documentation/hearth-plan-history.md).
`documentation/hearth-migration/` records the flake migration (phases 0-5).

## 2. Confirmed decisions (2026-08-21)

Statements only — rationale in
[`hearth-decisions.md`](../../documentation/hearth-decisions.md).

1. **Role: headless home server.** The Hyprland desktop is transitional.
2. **Hardware:** 4 TB IronWolf (`COLD`), ethernet switch, Pi Zero W. Two-tier
   storage. *Corrected 2026-08-30:* no spare TP-Link — the AX3000 is
   `AncientGlade`, live on the wall; the only spare is a GL.iNet GL-SFT1200.
3. **Jellyfin consolidates on Hearth.** Dropping `hosts/Tawa/jellyfin.nix` is
   deliberate, not a parity violation.
4. **Media never lives on the NVMe** — that tier is OS, Nix store, service
   state and Jellyfin metadata/transcode cache.
5. **NixOS modules over Docker** for every service.
6. **Secrets:** Bitwarden Pro is the human vault; sops-nix delivers to the host.
7. **Tailscale** for remote streaming and the special website. **No WAN port
   forwarding, ever.**
8. **Updates:** automatic remote-dev deployment, but **no unsupervised
   switching of shared files on `main`** — guardrails in H7.
9. **Acquisition: seedbox-first.** Local downloads only through a VPN. **Zero
   local seeding regardless of path.**
10. **USB topology:** one powered UASP hub on the **USB-C port** carries HDD and
    fans — fans on its power rail, not a data port; the PSU must cover spin-up
    plus fans. **The USB-A port stays free** as the recovery port.
11. **GitOps:** push-based first, then comin. **Superseded by decision 21.**
12. **Secrets: sops-nix** on-host, **Bitwarden Pro as master vault**. Confirmed.
13. **Network interim:** TV and Hearth stay on GiGstreem Wi-Fi; the wired LAN is
    deferred. Still current — the blocker is that the TV and phones drop on
    AncientGlade, not DHCP reservations.
14. **Jellyfin migration: fresh start.** No `/var/lib/jellyfin` state copy.
15. **Wired NIC:** a separate USB-A gigabit ethernet adapter (to buy).
16. **Public web presence:** serverless webapp at `wiztow.org`, with intranet
    subdomains such as `tv.wizt.org`.
17. **Idle behavior:** Hearth never suspends on idle; the only suspend trigger
    is lid close while on battery.
18. **GiGstreem has no DHCP reservations.** H1 pins **172.16.141.38/24** on the
    `GiGstreem` NM profile; the PSK stays on-box, **never in the flake**.
19. **Seedbox: Ultra.cc**, pulling into `/mnt/cold/share`.
20. **Agent sessions stay on AncientGlade** until remote development works.
    Flip SSID for TV playback tests, then come back — **do not solve this with
    another LAN hack.**
21. **GitOps end state: push-based only.** `hearth-deploy` is the deploy path;
    **comin is cancelled** (supersedes decision 11).

## 3. Target architecture

Interim: Hearth and the TV sit on GiGstreem Wi-Fi (decisions 13, 20). Final
(the on-hand AX3000 fills the "new router" slot):

```
Internet ── new router ── TP-Link router (NAT, dedicated server LAN)
                               │
                         ethernet switch
                         ┌─────┼──────────┐
                      Hearth  Pi Zero W  (future wired clients)
                    (USB-A NIC (Pi-hole
                     or hub NIC) DNS)
Tailscale mesh: Hearth ⇄ Surface Go 2 ⇄ phones ⇄ Ultra.cc (H8)
LG TV: local LAN path to Jellyfin (cannot run Tailscale) — same LAN as Hearth
```

- **Tier 1 (NVMe 238 GB):** `/`, Nix store, `/var/lib/jellyfin`, service state.
- **Tier 2 (HDD 4 TB, USB):** `/mnt/cold` — `media/{movies,tv,music}`, `share/`
  for seedbox/archives, restic snapshots. Mounted by UUID with `nofail`.
- **Services (NixOS modules only):** jellyfin, tailscale, caddy (tailnet-only),
  syncthing, restic, openssh; later the notification hook and deploy agent.

## 4. Phases

Ordering rule: **do not remove the desktop (H4) until H0-H1 give two
independent remote paths in** (SSH over LAN + SSH over Tailscale). The desktop
is currently the only recovery console.

| Phase | State | Detail |
|---|---|---|
| H0 | **shipped in config** | [remote-access](../../documentation/hearth-remote-access.md) |
| H1 | deferred (better router) | [network-lan](../../documentation/hearth-network-lan.md) |
| H2 | **shipped** | [storage-cold](../../documentation/hearth-storage-cold.md) |
| H3 | shipped (sidecars) | [caption-latency](../../documentation/hearth-caption-latency.md) |
| H4 | not started | [headless-flip](../../documentation/hearth-headless-flip.md) |
| H5 | shipped (restic v1) | [`restic.md`](./restic.md) |
| H6 | landed (tailnet-only) | [remote-surface](../../documentation/hearth-remote-surface.md) |
| H7 | **shipped (push-based)** | [gitops-decision](../../documentation/hearth-gitops-decision.md) |
| H8 | in progress | [ingest-pipeline](../../documentation/hearth-ingest-pipeline.md) |

**Each phase's rules are collected in §8.**

### H0 — Remote access + prerequisites — **shipped in config**
Key-only `sshd` + Tailscale (`hosts/Hearth/remote-access.nix`). `Host hearth`
is the OpenSSH path deploys use; `hearth-deploy doctor` from Tawa is the check.

### H1 — Wired network + DNS (deferred until better router)
Interim: **172.16.141.38/24** pinned on the `GiGstreem` NM profile, DNS
`1.1.1.1,8.8.8.8`. Final: USB-A gigabit adapter → switch → TP-Link LAN with a
static lease, Pi-hole as LAN DNS.

### H2 — Storage (HDD tier) — **shipped**
COLD at `/mnt/cold`, `nofail` + `x-systemd.device-timeout=10s`; dirs
`media/{movies,tv,music}` and `share/`. `hearth-disk park` before unplugging —
`hearth-deploy health` is expected to fail while parked. Its NTFS semantics
constrain everything that writes there: §8.

### H3 — Jellyfin consolidation (Tawa → Hearth)
One Jellyfin, on Hearth, with fresh server state (decision 14). First-play
caption lag is resolved by **external sidecars, no service**: Jellyfin 10.11
serves `{name}.{lang}.default.{ass|srt}` beside the video in ~107 ms, written
by `hearth-extract-sidecars`. Disabling `EnableSubtitleExtraction` is **not** a
fix — it removes captions instead.

### H4 — Headless flip
`profiles/media-server.nix` drops the desktop modules and shrinks home-manager
to shell-only; the previous generation in systemd-boot is the recovery path.
Lid policy beyond `HandleLidSwitchExternalPower = ignore` is open question 4.

### H5 — Secrets
**sops-nix** with an age key per host; private keys and master copies live in
**Bitwarden Pro**. **Restic (v1)** backs up Jellyfin state, Tailscale identity,
ACME certs, the host age key and builder `config.nix` copies to
`/mnt/cold/backups/hearth-restic`, 7 daily + 4 weekly. Acceptance: a fresh
install re-keys from Bitwarden alone.

### H6 — Remote surface (wiztow.org + streaming)
Caddy proxies Jellyfin at `https://tv.wizt.org`, bound to tailnet
`100.84.222.78:443` — tailnet-only, not Funnel. TLS is Let's Encrypt DNS-01 via
Cloudflare, forced by the apex's `HSTS includeSubDomains`. The TV still uses
`http://172.16.141.38:8096`.

### H7 — Automatic remote-dev updates (GitOps) — **shipped (push-based)**
`hearth-deploy` over OpenSSH/Tailscale, no agent on the server. The pin is
**`deploy/hearth`**, the activator `nixos-rebuild --target-host`; comin is
cancelled (decision 21). Its five guardrails are rules: §8. **Before revisiting
any puller:** enforce the path filter server-side on `deploy/hearth`.

### H8 — Acquisition pipeline (seedbox-first)
Ultra.cc slot acquired 2026-08-30. Syncthing pulls into `/mnt/cold/share` over
two unidirectional folders; ingest hardlinks into `media/{movies,tv,music}` then
runs `hearth-extract-sidecars --one <file>`. Sonarr/Radarr and Bazarr run on the
slot, so files arrive sorted and with real `.srt` sidecars. The ingest UI stays
**last**.

## 5. Risk register (from the audit)

Every row is resolved or mitigated; the table is kept as a closed audit
artifact in
[`hearth-plan-history.md`](../../documentation/hearth-plan-history.md).

## 6. Open questions

1. **Better router:** ~~which model / when~~ — **diagnosed 2026-08-30; likely
   no purchase.** `AncientGlade`'s merged SSID with Smart Connect
   deauthenticates the TV and phones mid-use; the link is healthy while
   associated, which is why stationary Tawa never drops. **The fix is free:**
   split the SSIDs, pin the TV to 5 GHz, pin the channel, update firmware.
   Still open is whether that holds — if it does, move the TV and Hearth onto
   AncientGlade for a real DHCP reservation, which is all the TV needs. Buy an
   **access point** only if 5 GHz coverage at the TV proves short. Diagnosis:
   [`router-recommendations.md`](../../documentation/router-recommendations.md),
   [`network-fault-findings.md`](../../documentation/network-fault-findings.md).
2. **Ultra.cc sync path:** ~~tailnet join or Ultra's own protocol?~~ —
   **resolved 2026-08-30: plain Syncthing**, whose TLS and device-ID auth with
   relay fallback already cross the double NAT. See H8.
3. **`tv.wizt.org` exposure:** tailnet-only (simplest) or public via Tailscale
   Funnel (Jellyfin auth is the only gate)? Pick when H6 lands.
4. **Battery policy after headless (H4):** keep lid-close-on-battery = suspend
   (preserves the cell, kills streams in an outage) or treat the battery as a
   small UPS? Idle suspend is already ruled out (decision 17).

## 7. What already matches (no rework needed)

Named flake host with generated hardware config; the Jellyfin module pattern
(host-local, `openFirewall`, tmpfiles, VAAPI for Ice Lake); lid ignore-on-AC;
parity guardrail discipline for shared files; `legacy/surface-standalone` and
systemd-boot generation rollback.

## 8. Rules index

Every rule that binds work on Hearth, stated once. **§8 is the contract; §4 is
the status.**

**Storage / COLD (H2)**
- **Do not format COLD.** Mount by UUID with `nofail`; never the old
  `/srv`-style or unprefixed media mount.
- **Media never lives on the NVMe** (d4).
- **Do not `chown`/`chmod` on COLD and do not add a service that tries** —
  `chmod(2)` returns `EPERM`, so Syncthing needs `ignorePerms` on both folders.
  Write access comes from group membership (`wiz` is in `jellyfin`).
- **Hardlink, never move**; both paths must be on `/mnt/cold`.
- **Permission, ownership and linking changes need a real switch** —
  `hearth-deploy build` cannot see them.
- **Do not "fix" `media/music` back to `Music`** — ntfs-3g is case-sensitive
  and a mismatch leaves the tree unscanned beside an empty twin.
- **A rename must change the disk path and
  `/var/lib/jellyfin/root/default/Music/{music.mblink,options.xml}` together**,
  then restart `jellyfin` and rescan.
- **`music.mblink` must carry no trailing newline** — `printf`, not `echo`.
  `hearth-healthcheck.sh` fails the deploy on a newline, a missing directory,
  or a `.mblink`/`options.xml` disagreement in either direction.

**Network (H1, d7, d18, d20)**
- **No WAN port forwarding, ever.**
- **The Pi Zero W is operator-managed and must never become a host in this
  flake.**
- **Keep DNS at `1.1.1.1,8.8.8.8` in `common/lan.nix`** — the ISP resolver plus
  MagicDNS hung `cache.nixos.org`.
- The GiGstreem PSK stays on-box, **never in the flake**.
- **Do not solve agent-session reachability with another LAN hack.**

**Remote access and surface (H0, H6)**
- **Do not re-open H0 as a flake task.**
- **Deploys must use the OpenSSH path, not Tailscale SSH** — `nix-copy` needs a
  real sshd.
- **Nothing on Hearth listens on WAN for the `tv.wizt.org` vhost**, and Hearth
  is **not a public web server**.
- **Do not keep `tls internal` on a `wizt.org` name** — HSTS on the apex makes
  it un-exceptable in Firefox.

**Deploys and GitOps (H4, H7, d8)**
- **Do not remove the desktop (H4) until two independent remote paths exist.**
- **Use `boot` + reboot for the headless flip and any kernel/initrd/disk change
  — never `switch`.**
- **No unsupervised switching of shared files on `main`; do not auto-switch
  `main`.**
- **Deploy only from `deploy/hearth`, never `main`** — promotion is a
  deliberate human fast-forward.
- **Do not auto-apply commits touching `common/`, `home/`, `profiles/`,
  `flake.nix` or `flake.lock`** unless explicitly tagged for deployment.
- **`nixos-rebuild test` is not a rollback mechanism** — a failed health check
  switches back explicitly.

**Secrets (H5)**
- **GitHub Actions secrets are CI-only, never host-side secret delivery.**
- **Do not snapshot `/mnt/cold/media` or `/nix/store`.**
- **No plaintext secret in the repo**; slot identifiers stay encrypted in
  `secrets/hearth-seedbox.yaml`.

**Ingest (H8, d9, d19)**
- **Zero local seeding in both paths**; local downloads only through a VPN,
  upload hard-capped at 0.
- **Do not install Ultra's WireGuard** for the sync leg.
- **Share `~/library`, never the raw torrent directory** — otherwise
  scene-named files arrive and the seeding copy double-counts against quota.
- **Two unidirectional Syncthing folders, never one bidirectional** — Send &
  Receive round-trips deletions into an unbounded re-grab loop.
- **`/mnt/cold/share` is a landing zone, never the library**; moving out of a
  Receive Only folder leaves it permanently out of sync.
- **No usenet stack, no Plex-ecosystem tools, no second `*arr` instances, no
  serving apps** on the slot — only Hearth serves the library.
- `hearth-extract-sidecars` runs on demand and has **no timer** (H3).

**This file**
- **Do not move, rename or retitle it, never renumber its sections, decisions
  or phases, and keep evidence in `documentation/` rather than here.**

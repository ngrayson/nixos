# Hearth Home Server — Source of Truth

**v2 — 2026-08-21.** This document supersedes the original "NixOS Home Server
System Canvas" (written with incomplete context: wrong hardware, three-tier
storage, pre-migration state) and consolidates it with the 2026-08-21 audit
and the decisions confirmed the same day. When this file and older docs
disagree, this file wins. The `documentation/hearth-migration/` docs remain as
the historical record of the flake migration (phases 0-5, complete).

---

## 1. Corrected context

The original canvas was written with wrong hardware, a three-tier storage
plan, and a pre-migration view of the machine. That reconciliation table and
the audit's risk register (every row resolved or mitigated) live in
[`documentation/hearth-plan-history.md`](../../documentation/hearth-plan-history.md).

Current live facts (2026-08-21, post-H2): hostname `Hearth`, sshd key-only,
Jellyfin `Healthy`. **Wi-Fi is AncientGlade `192.168.0.133` during agent
sessions** (Cursor cannot reach this machine on GiGstreem yet). GiGstreem
profile stays pinned at **172.16.141.38/24** for TV hosting. Tailnet
`ngrayson.github`: `hearth.tail6cd822.ts.net` = `100.84.222.78`. HDD is
Seagate IronWolf 4 TB NTFS `COLD` at `/mnt/cold` (`media/` + `share/`).
`/srv/media` emptied. Unplug drill passed (`nofail`).

## 2. Confirmed decisions (2026-08-21)

1. **Role: headless home server.** The Hyprland desktop from the migration is
   transitional and will be removed once remote access is proven.
2. **Hardware on hand:** 4 TB Seagate IronWolf HDD (`COLD` at `/mnt/cold`), ethernet switch,
   Raspberry Pi Zero W (Pi-hole/DNS — not yet deployed). Two-tier storage.
   **Corrected 2026-08-30:** there is no *spare* TP-Link router. The TP-Link
   AX3000 is `AncientGlade`, active on the wall (WAN `172.16.141.4` → LAN
   `192.168.0.0/24`), and it supports Address Reservation. The only spare
   router is a GL.iNet GL-SFT1200 "Opal" (Wi-Fi 5, 3× gigabit ports,
   OpenWrt-based). See
   [`documentation/router-recommendations.md`](../../documentation/router-recommendations.md).
3. **Jellyfin consolidates on Hearth.** `hosts/Tawa/jellyfin.nix` will be
   removed from Tawa's imports (deliberate, coordinated change — not a parity
   violation).
4. **Media never lives on the NVMe** (238 GB is too small). NVMe = OS, Nix
   store, service state, Jellyfin metadata + transcode cache. HDD = media
   library + local archives.
5. **NixOS modules over Docker** for every service.
6. **Secrets:** Bitwarden Pro (and/or GitHub) as the human vault. See H5 for
   how that reaches the host (sops-nix recommended as the delivery mechanism —
   a vault alone cannot decrypt secrets at activation time).
7. **Tailscale** for remote streaming and the special website. No WAN port
   forwarding, ever.
8. **Updates:** automatic remote-dev deployment wanted ("something strong"),
   but **no unsupervised switching of shared files on `main`** — guardrails in
   H7. Builds may run on-box (after freeing NVMe space) or on a stronger host
   with only the switch happening on Hearth.
9. **Acquisition: seedbox-first.** Local downloads allowed only through a VPN.
   Zero local seeding regardless of path.

### Decisions round 2 (2026-08-21 PM)

10. **USB topology:** one high-quality **powered USB hub with UASP** plugs
    into the **USB-C port** (best bandwidth; Surface Connect handles
    charging), hosting the HDD and the server-rack fans (fans on the hub's
    power rail, not a data port; PSU must cover HDD spin-up + fans). The
    **USB-A port stays free** as the recovery/expansion port (keyboard for
    console rescue post-headless, or a gigabit ethernet adapter later).
11. **GitOps:** start **push-based (deploy-rs over Tailscale)**; graduate to
    **comin on `deploy/hearth`** once the health-check script exists.
    **Superseded by decision 21** — comin cancelled 2026-08-25.
12. **Secrets:** **sops-nix** on-host, **Bitwarden Pro as master vault** for
    one-time setup/re-keying. Confirmed.
13. **Network interim:** TV and Hearth both stay on **GiGstreem Wi-Fi, no
    static route**. The TP-Link/switch wired LAN is **deferred until a better
    router is acquired** (H1 re-scoped accordingly).
    **Still current as of 2026-08-30, for a corrected reason.** The blocker is
    not that no router can do DHCP reservations — the on-hand AX3000
    (`AncientGlade`) can. It is that **the TV and phones drop on AncientGlade**
    and have been moved to GiGstreem, where they are stable but outside the
    intranet. Until those drops are diagnosed, moving clients onto the server
    LAN trades working Wi-Fi for broken Wi-Fi. See
    [`documentation/router-recommendations.md`](../../documentation/router-recommendations.md).
14. **Jellyfin migration:** **fresh start** on Hearth — no `/var/lib/jellyfin`
    state copy from Tawa; only media files transfer.

### Decisions round 3 (2026-08-21 eve)

15. **Wired NIC:** a separate **USB-A gigabit ethernet adapter** (to buy) —
    the hub keeps all its ports for storage/fans; USB-A stops being the
    rescue port once the machine is wired, which is fine post-H0 (SSH is the
    recovery path by then).
16. **Public web presence:** a **serverless webapp on Vercel (or similar) at
    `wiztow.org`**; parts of the intranet exposed as subdomains, e.g.
    **`tv.wizt.org`** for the home media surface. H6 re-scoped around
    this.
17. **Idle behavior (verified in config):** Hearth never suspends on idle —
    `hypridle` only locks (300 s) and turns the display off (600 s); logind's
    `IdleAction` is at its default of ignore. The only suspend trigger is
    **lid close while on battery**. Confirmed streaming works lid-closed on
    AC. The sole remaining H4 policy choice is what to do on battery.
18. **GiGstreem has no DHCP reservations.** Interim H1 pins **172.16.141.38/24**
    on Hearth's existing NetworkManager `GiGstreem` profile (PSK stays on-box,
    not in the flake). Collision risk if Hearth is offline and the ISP pool
    reissues .38 — accepted until the better router / wired LAN.
19. **Seedbox: Ultra.cc.** Account and slot ready before H8. Syncthing (or
    rsync/SSH) pulls completed files into `/mnt/cold/share`. Tailnet join vs
    native Syncthing is decided when H8 lands. Zero local seeding still holds.
20. **Agent sessions stay on AncientGlade** (`192.168.0.133`) until remote
    development works (SSH/Tailscale from Go 2). Cursor cannot reach Hearth
    on GiGstreem. TV hosting still requires GiGstreem `172.16.141.38` — flip
    SSID for playback tests, then come back to AncientGlade to continue
    this agent. Fixed by H0-from-elsewhere / H7, not by another LAN hack.

### Decisions round 3 (2026-08-25)

21. **GitOps end state: push-based only.** `hearth-deploy` is the deploy path
    and **comin is cancelled** (supersedes decision 11). Comin implements one
    of the five H7 guardrails; its one real gain — applying changes without
    Tawa awake — is exactly what breaks guardrail 2, because the path filter
    only runs when the pin advances through `hearth-deploy`. Any future puller
    needs that filter enforced server-side on `deploy/hearth` first. See H7.

## 3. Target architecture

```
Interim (now, decisions 13 + 20):
Internet ── GiGstreem ── Wi-Fi: LG TV (Jellyfin at 172.16.141.38 when Hearth
                    │        is on this SSID)
                    └── AncientGlade (NAT) ── Hearth 192.168.0.133
                         (Cursor agent sessions until remote-dev works)

Final (no purchase required as of 2026-08-30 — the on-hand AX3000 fills the
"new router" slot below; see documentation/router-recommendations.md):
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

- **Tier 1 (NVMe 238 GB):** `/`, Nix store, `/var/lib/jellyfin` (metadata,
  transcode temp), service state, Syncthing staging if space allows.
- **Tier 2 (HDD 4 TB IronWolf, USB):** `/mnt/cold` — library under
  `media/{movies,tv,music}`, plus `share/` for seedbox/archives.
  Restic/local snapshots. Mounted by UUID with `nofail` so boot never hangs
  on a missing USB disk. Never the old `/srv`-style or unprefixed media mount.
- **Services (NixOS modules only):** jellyfin, tailscale, caddy (tailnet-only
  vhosts), syncthing, restic, openssh, and later the notification hook +
  deployment agent.

## 4. Phases

Ordering rule: **do not remove the desktop (H4) until H0-H1 give two
independent remote paths in** (SSH over LAN + SSH over Tailscale). The
desktop is currently the only recovery console.

### H0 — Remote access + prerequisites — **shipped in config**
- `hosts/Hearth/remote-access.nix` enables key-only `sshd` and Tailscale
  (`--ssh`, `--accept-dns=false`). Pubkeys: GitHub `ngrayson` ed25519 and
  Tawa `wiz@Tawa` (`~/.ssh/id_ed25519` on the builder).
- **Ops accept (2026-08-22, from Tawa):** Hearth was on GiGstreem
  `172.16.141.38` (AncientGlade `192.168.0.133` had no route).
  `sshd` + `tailscaled` + `jellyfin` + `display-manager` active; trusted-users
  `@wheel` and passwordless sudo already on the running generation (no
  on-box switch). `ssh hearth` over MagicDNS was **Tailscale SSH** (doctor
  warned: nix-copy wants sshd). OpenSSH path is LAN `172.16.141.38` with
  the Tawa key — `Host hearth` in `home/programs/ssh-hearth.nix` now targets
  that IP. MagicDNS Tailscale SSH remains as `Host hearth-tailnet`.
  `hearth-deploy doctor` from Tawa is the check. Do not re-open H0 as a
  flake task.
- Extra Go 2 / Theseus keys and a recorded GC of old Plasma generations
  are still leftover ops — not missing modules.

### H1 — Wired network + DNS (deferred until better router)
- Interim (now): Hearth and the LG TV both on GiGstreem Wi-Fi. The ISP
  gateway has **no DHCP-reservation UI** (decision 18), so Hearth pins
  **172.16.141.38/24** on the existing `GiGstreem` NM profile (gateway
  `172.16.141.1`). DNS is **`1.1.1.1,8.8.8.8`** in `common/lan.nix` on
  purpose — ISP `172.16.141.1` plus MagicDNS/`accept-dns` hung
  `cache.nixos.org` on GiGstreem. MAC `c8:34:8e:21:97:1b` is informational only.
- Later (new router acquired): USB-A gigabit ethernet adapter (decision 15)
  → switch → TP-Link LAN; static lease; prefer wired over Wi-Fi.
- Pi Zero W: Pi-hole as LAN DNS (`hearth.home` etc.) when the wired LAN
  lands. Out of scope for this flake unless we NixOS-ify the Pi later.
- Acceptance (interim): Hearth holds 172.16.141.38 after reconnect; TV plays
  from that IP.
  Acceptance (final): Jellyfin reachable via wired IP; LAN DNS resolves.

### H2 — Storage (HDD tier) — **shipped**
- Disk is a **4 TB Seagate IronWolf** (ST4000NE001) NTFS volume **COLD**.
  **Do not format.** Mounted at `/mnt/cold` with `nofail` +
  `x-systemd.device-timeout=10s`. `/srv/media` emptied; unplug drill passed.
- **USB link fixed (2026-08-25 PM).** The enclosure used to negotiate
  **480 Mb/s / USB 2.10** behind a USB2.1 hub (`usb3/3-4/3-4.1`), capping
  reads at 40 MB/s — the cause of the caption delay under H3. Moved to the
  laptop's USB-C port on a SuperSpeed-rated cable: now enumerates at
  **10 Gb/s** (`usb2/2-1/2-1.1`) and cold-reads at **197 MB/s** (platter
  limit — link no longer the bottleneck). Two gotchas for next time: the
  first C-to-C cable tried was charge-only (enumerated USB2 with zero
  SuperSpeed link, no error anywhere), and the enclosure does not re-attach
  on plug-in alone — it needs a **power cycle** after any cable move. The
  GenesysLogic hub that shows up with COLD is *inside the enclosure*; it
  power-cycles with the drive.
- `hearth-disk park` before unplugging COLD; replug remounts and starts
  Jellyfin; `hearth-deploy health` is expected to fail while parked.
- Dirs: `/mnt/cold/media/{movies,tv,music}` (Jellyfin) and `/mnt/cold/share`.
  Leave `Anime/`, `Downloads/`, … at the volume root. There is no `Music`
  there; the audio archive lives at `media/music`.
- **COLD does not support `chmod`, and anything writing to it must be told so.**
  The volume is mounted `uid=0 gid=989 umask=0002` (`hosts/Hearth/host.nix`),
  so ownership and permission bits come from the *mount options* — every file
  is `root:jellyfin` regardless of who wrote it, and `chmod(2)` returns
  `EPERM`. Do not `chown`/`chmod` anything on COLD, and do not add a service
  that tries to. This has cost real time twice: Syncthing's default
  permission-syncing made every pull into `/mnt/cold/share` die with
  `handling dir (setting permissions): chmod ...: operation not permitted`,
  aborting the whole folder cycle with exponential backoff while the files sat
  as `.syncthing.*.tmp` and were never renamed into place — with the folder
  still reporting `idle`, which reads like a slow peer rather than an error.
  The fix is `ignorePerms` on both folders (`hosts/Hearth/syncthing.nix`).
  Group membership is how processes get write access: `wiz` is in `jellyfin`
  (`hosts/Hearth/jellyfin.nix`), which is what makes `umask=0002` writable.
- **Hardlinks do work on COLD** — verified 2026-08-31: `ln` across directories
  gives link count 2 and a shared inode, and removing the source leaves the
  target intact at count 1. This is what lets H8 ingest hardlink out of
  `share/` into `media/` for free instead of copying, and it is why moving is
  never necessary. Both paths must be on `/mnt/cold`; a link across
  filesystems fails.
- Neither of the two constraints above is visible to `hearth-deploy build`.
  Filesystem semantics on COLD can only be validated by activating and
  watching the service, so treat any change touching permissions, ownership,
  or linking on that volume as needing a real switch before it is called done.
- ntfs-3g mounts COLD case-sensitively, so `music` and `Music` are two
  different directories. The archive shipped as `Music` and was renamed to
  lowercase to match the tmpfiles rule. Do not "fix" the case back: a mismatch
  leaves the populated tree unscanned beside an empty twin that Jellyfin logs as
  "inaccessible or empty, skipping".
- Casing has **three** sides, and renaming the disk only fixes one. The library
  path also lives in server state, outside Nix, at
  `/var/lib/jellyfin/root/default/Music/{music.mblink,options.xml}`. Change both
  whenever the directory moves, then restart `jellyfin` and rescan.
- `music.mblink` must hold the path with **no trailing newline** (21 bytes for
  `/mnt/cold/media/music`). Jellyfin does not trim it; a newline becomes part of
  the lookup and reads as the same "inaccessible or empty" skip as a case
  mismatch. Write it with `printf`, not `echo`, or edit the folder in
  Dashboard → Libraries.
- `hearth-healthcheck.sh` now fails the deploy if any library `.mblink` ends in a
  newline, names a directory that does not exist, or disagrees with its
  `options.xml` **in either direction** — a stale `<Path>` a rename left behind
  fails too, since Jellyfin keeps scanning it. A missing library root is a
  failure rather than a skipped check, so the probe cannot quietly disappear if
  Jellyfin's layout moves. An empty music shelf should never again survive a
  green switch.

### H3 — Jellyfin consolidation (Tawa → Hearth)
- Copy Tawa's media files into `/mnt/cold/media` (rsync over LAN/tailnet).
- Remove `./jellyfin.nix` from `hosts/Tawa/host.nix` imports (keep the file
  or delete it — imports list is the switch). Rebuild Tawa.
- **Fresh start** for server state (decision 14): no `/var/lib/jellyfin`
  copy; users/watch history recreated on Hearth.
- Acceptance: one Jellyfin on the network; clients repointed.
- **Captions lag on first play — COLD's USB2 link was why (fixed).**
  Embedded ASS/SRT tracks are extracted on demand with
  `ffmpeg -i <file> -map <n> -c:s copy`, which demuxes the *whole* container,
  so the picture runs uncaptioned for roughly `filesize / read speed`. The USB
  fix (H2) took COLD from 40 MB/s to 197 MB/s, which shortened but did not
  close the gap: ~8s on a 1.45 GB episode, 31s on a 5.80 GB movie.
  - **Resolution: external sidecars, no service.** Jellyfin 10.11 picks up a
    `{name}.{lang}.default.{ass|srt}` next to the video as `IsExternal` and
    serves it in ~107ms with no `SubtitleEncoder` pass.
    `hearth-extract-sidecars` (`hosts/Hearth/extract-sidecars.nix`) is the
    idempotent manual pass — text tracks only, **no timer**. New arrivals call
    the same binary from H8 ingest via `--one`. Bazarr on the seedbox writes
    real `.srt` upstream (H8), which demotes this to a fallback.
  - Not a fix: `EnableSubtitleExtraction` only *permits* on-the-fly
    extraction; disabling it removes captions rather than speeding them up.
    Jellyfin 10.11 has no pre-extract-during-scan option.
  - Measurements, the 1336-file subtitle inventory, and the font-attachment
    tail: [`documentation/hearth-caption-latency.md`](../../documentation/hearth-caption-latency.md).

### H4 — Headless flip
- New `profiles/media-server.nix`: base.nix + openssh + tailscale + jellyfin
  prerequisites; **no** SDDM/Hyprland/PipeWire-desktop/HM GUI modules.
- Slim HM shrinks to shell-only (`zsh`, `git`, `fastfetch`, `micro`) — the
  Ghost theme survives in kitty/fastfetch rendered by *client* terminals over
  SSH; wallpaper/Hyprland/quickshell/dunst/albert are dropped.
- Keep `boot` + reboot for the flip; previous desktop generation remains in
  systemd-boot as the recovery path.
- Lid policy: with no session, logind still governs — keep
  `HandleLidSwitchExternalPower = ignore`; consider `HandleLidSwitch =
  ignore` too since the battery-as-UPS role means AC loss should not suspend
  the server (revisit: suspend-on-battery kills streams but saves the cell).
- Acceptance: boots to multi-user (no greeter), all services up, SSH +
  Tailscale reachable, power draw acceptable.

### H5 — Secrets
- **Confirmed (decision 12):** **sops-nix** with an age key per host; the age
  private keys and all master copies live in **Bitwarden Pro** (one-time
  setup / re-keying vault). GitHub (Actions secrets) only for CI builds,
  never as host-side secret delivery.
- First consumers: Tailscale auth key (if pre-auth used), Discord webhook
  URL, Restic repo password, seedbox credentials, Syncthing device IDs.
- Acceptance: no plaintext secret in the repo; a fresh Hearth install can be
  re-keyed from Bitwarden alone.
- **Restic (v1):** `hosts/Hearth/restic.nix` backups Jellyfin state (no
  transcodes/cache), Tailscale identity, ACME certs, the host age key, and
  builder `config.nix` copies under `/var/lib/hearth-intranet/config/`.
  Repo is `/mnt/cold/backups/hearth-restic` (7 daily + 4 weekly). Restore
  when and how: [`hosts/Hearth/restic.md`](./restic.md) (Conveyor tag
  `restic`). The flake still builds the OS. Do not snapshot
  `/mnt/cold/media` or `/nix/store`. Password is
  `secrets/hearth-restic-password.yaml` (Bitwarden → sops). Missing COLD
  fails only the backup unit. `hearth-deploy` copies gitignored widget
  `config.nix` files after switch/boot.

### H6 — Remote surface (wiztow.org + streaming)
- **Public site (decision 16):** serverless webapp on Vercel (or similar) at
  `wiztow.org`. Lives outside this flake; Hearth is not a public web server.
- **Intranet subdomain (landed, tailnet-only — not Funnel):** Caddy on Hearth
  (`hosts/Hearth/caddy.nix`) reverse-proxies Jellyfin at
  `https://tv.wizt.org`, bound to tailnet IPv4 `100.84.222.78:443` only.
  Funnel stays a future card.
- **DNS (operator):** A `tv.wizt.org` → `100.84.222.78`. Tailnet split DNS
  forwards `wizt.org` to Cloudflare. The name may resolve off-tailnet; TCP/TLS only
  works for tailnet members. TLS is Let's Encrypt DNS-01 (`security.acme` +
  lego `cloudflare`) because the public apex sends
  `HSTS includeSubDomains` — Caddy `tls internal` cannot be excepted in
  Firefox. Secret: `secrets/acme-cloudflare.env` (`CLOUDFLARE_DNS_API_TOKEN`).
  Host the `wizt.org` zone on Cloudflare (no GCP). Apex A records may still
  point at Rebrandly until the public site has a new home. Do not keep
  `tls internal` on a `wizt.org` name.
- **TV:** still `http://172.16.141.38:8096` on GiGstreem (Jellyfin
  `openFirewall` unchanged). Put that LAN IP on the intranet page later so
  local users do not need DHCP reservations.
- Remote streaming path: Jellyfin over Tailscale (Go 2, phones).
- Acceptance: `https://tv.wizt.org` serves Jellyfin for tailnet devices;
  nothing on Hearth listens on WAN for this vhost.

### H7 — Automatic remote-dev updates (GitOps) — **shipped (push-based)**
**Decided (decision 11, closed by decision 21):** push-based deploys via
`hearth-deploy` over OpenSSH/Tailscale (no agent on the server). The pin is
**`deploy/hearth`**. Activator is `nixos-rebuild --target-host` (deploy-rs
cannot `boot`; same path filter). **comin is cancelled** — see "Why not comin"
below. Do not auto-switch `main`.

Guardrails that answer "unsupervised switch on main" regardless of tool:
1. Hearth deploys from a **dedicated branch** (e.g. `deploy/hearth`), never
   `main`. Promotion = fast-forwarding that branch, a deliberate human act
   that can still be done remotely in seconds.
2. Agent refuses to auto-apply commits touching `common/`, `home/`,
   `profiles/`, `flake.nix`, or `flake.lock` unless the commit is explicitly
   tagged for deployment (path filter before build).
3. Kernel/initrd/disk changes use `boot` + scheduled reboot, not `switch`
   (matches the repo's existing os-rebuild rule).
4. Builds: on-box is acceptable after H2 frees the NVMe (media off, GC run);
   preferred long-term is build on Tawa/CI + `nix copy` over the tailnet,
   with Hearth only switching. `nixos-rebuild test` is *not* a rollback
   mechanism — health-check failures trigger `switch` back to the previous
   generation explicitly.
5. Notifications (Discord webhook via H5 secret) on start/success/rollback.

**Why not comin (2026-08-25).** `hearth-deploy` already satisfies all five
guardrails above; comin satisfies one (polling a dedicated branch). Its only
real gain — applying changes with Tawa asleep — is exactly what breaks
guardrail 2, because the path filter works *because* the pin only advances
through `hearth-deploy`. **Prerequisite for revisiting any puller:** enforce
the path filter server-side on `deploy/hearth` (branch protection plus a
required check running `refuse_shared_deploy_paths` logic). With that in place
`nixos-autodeploy` is the better candidate than comin. Full analysis:
[`documentation/hearth-gitops-decision.md`](../../documentation/hearth-gitops-decision.md).

### H8 — Acquisition pipeline (seedbox-first)
- **Provider (decision 19): Ultra.cc** — **slot acquired 2026-08-30.** The
  seedbox pack's blocker is cleared; pairing proceeds once device IDs exist.
- Seedbox downloads; **Syncthing** pulls completed files to
  `/mnt/cold/share`; tag-based routing to `/mnt/cold/media/{movies,tv,music}`
  via a small systemd path unit or the future homepage API.
- **The sync leg needs no tailnet join and no VPN (resolves open question 2).**
  Ultra.cc's app catalogue offers no Tailscale, and Syncthing does not need
  one: device-ID auth over its own TLS, with hole-punching and relay fallback
  covering Hearth's double NAT. Do not install Ultra's WireGuard for this.
- **Share the organized tree, not the torrent directory.** Sonarr/Radarr run
  *on the seedbox* and hardlink from `~/torrents/done` into `~/library`; only
  `~/library` is shared with Syncthing. Sharing the raw torrent dir would send
  scene-named files to Hearth and double-count the still-seeding copy against
  Ultra's disk quota.
- **Two unidirectional Syncthing folders, not one bidirectional** (as-built
  2026-08-31): `hearth-library` (slot `~/library` Send Only → Hearth
  `/mnt/cold/share` Receive Only) carries acquisitions down;
  `hearth-upload` (Hearth `/mnt/cold/upload` Send Only → slot
  `~/hearth-upload` Receive Only, with File Versioning) carries existing COLD
  content up as a versioned offsite copy. A single Send & Receive folder would
  round-trip deletions: Hearth's routing step moving a file out of `share/`
  would delete it from the slot's `~/library`, and Sonarr/Radarr would mark the
  episode missing and re-grab it in an unbounded loop.
- **`/mnt/cold/share` is a landing zone, never the library.** Hearth must
  hardlink out into `media/{movies,tv}`, never move — moving out of a Receive
  Only folder leaves it permanently out of sync, and Syncthing's only offered
  remedy re-downloads everything.
- Because files then arrive already sorted into `movies/`/`tv/`, the
  tag-routing step above shrinks to a move rather than a classifier.
- **Seedbox app set (chosen 2026-08-30):** Syncthing, qBittorrent (+ qui),
  Prowlarr, Sonarr, Radarr, Bazarr. No usenet stack (no provider), no
  Plex-ecosystem tools (Hearth serves Jellyfin), no second `*arr` instances,
  and no serving apps — the library lives on COLD and only Hearth serves it.
  Autobrr only if private-tracker race timing demands it; FlareSolverr/Byparr
  only when a specific indexer asks for one.
- **Bazarr writes real `.srt` sidecars upstream**, which sync over alongside
  the media. That is the durable fix for the first-play caption delay, and it
  demotes the `hearth-extract-sidecars` pass below to a fallback for titles
  Bazarr finds no subtitles for.
- VPN-piped local download as fallback only: reuse the repo's existing VPN
  stack (`common/vpn-vortix.nix` stunnel/FrootVPN — server-safe subset) or a
  dedicated namespace so torrent traffic cannot leak; upload hard-capped at 0.
- Zero local seeding in both paths.
- After each ingest move into `media/{movies,tv}`, run
  `hearth-extract-sidecars --one <file>` so new titles get sidecars
  without waiting for another library-wide pass.
- The homepage/ingest UI from the original plan stays **last**, after H6-H7.
- **Slot runbook:**
  [`documentation/hearth-seedbox-runbook.md`](../../documentation/hearth-seedbox-runbook.md)
  — Ultra.cc Fair Usage limits, the host-native/container split that dictates
  how the apps reach each other, the directory tree, and the verification
  commands. Identifying values (slot username, hostname, Syncthing device and
  folder IDs) stay out of the clear in this public repo; they are encrypted in
  `secrets/hearth-seedbox.yaml` (`sops -d` to read).

## 5. Risk register (from the audit)

Every row is resolved or mitigated; the table is kept as a closed audit
artifact in
[`documentation/hearth-plan-history.md`](../../documentation/hearth-plan-history.md).

## 6. Open questions

1. **Better router:** ~~which model / when~~ — **diagnosed 2026-08-30; likely
   no purchase.** The fault is that the TV and phones drop **mid-use** on
   `AncientGlade`, which runs a **merged SSID with Smart Connect**. Smart
   Connect steers clients between bands by deauthenticating them, and cheap TV
   and phone radios often fail to re-associate. This explains why stationary
   Tawa never drops on the same AP, why latency measured fine (5.7 ms — the
   link is healthy *while associated*), and why a 2.4 GHz channel change did
   nothing. TWT and OFDMA are already disabled, so Smart Connect is the one
   known drop-causing feature left on. **Fix is free:** split the SSIDs, pin
   the TV to 5 GHz, pin the 5 GHz channel, update firmware. If that holds, move
   the TV and Hearth onto AncientGlade for a real DHCP reservation — which is
   what the TV actually needs, since it only wants Jellyfin at an address that
   never changes (a TV remote makes retyping painful) and does **not** need
   `home.wizt.org`. Buy an **access point** only if 5 GHz coverage at the TV
   proves short. See
   [`documentation/router-recommendations.md`](../../documentation/router-recommendations.md).
2. **Ultra.cc sync path:** ~~join the slot to the tailnet for Syncthing, or
   sync over Ultra's own protocol/SSH?~~ — **resolved 2026-08-30: plain
   Syncthing, no tailnet join and no WireGuard.** Ultra offers no Tailscale
   app, and Syncthing's own TLS plus device-ID auth with relay fallback
   already crosses the double NAT. See H8.
3. **`tv.wizt.org` exposure:** tailnet-only (private, simplest) or public
   via Tailscale Funnel (Jellyfin auth is the only gate)? Pick when H6 lands.
4. **Battery policy after headless (H4):** keep lid-close-on-battery =
   suspend (preserves the cell, kills streams in an outage) or ignore it and
   treat the battery as a small UPS? Idle suspend is already ruled out
   (decision 17).

## 7. What already matches (no rework needed)

Named flake host with generated hardware config; Jellyfin module pattern
(host-local, `openFirewall`, tmpfiles, VAAPI packages for Ice Lake); lid
ignore-on-AC; libinput/palm work (moot after H4 but harmless); parity
guardrail discipline for shared files; `legacy/surface-standalone` rollback
branch; systemd-boot generation rollback.

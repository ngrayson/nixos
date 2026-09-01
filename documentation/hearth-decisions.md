# Hearth confirmed decisions — full text and rationale

Rationale moved out of [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md) §2 on
2026-09-01, when that file was restructured into an index so it would stop
outgrowing Conveyor's 32,000-character overview cap for the `hearth` tag.
**Nothing here is superseded** except where a decision says so itself. plan.md
keeps every decision's statement and its number; this file keeps the reasoning
behind it. **Decision numbers are a public addressing scheme** — other files
cite them — so they are never renumbered in either file.

## Round 1 (2026-08-21)

1. **Role: headless home server.** The Hyprland desktop from the migration is
   transitional and will be removed once remote access is proven.
2. **Hardware on hand:** 4 TB Seagate IronWolf HDD (`COLD` at `/mnt/cold`),
   ethernet switch, Raspberry Pi Zero W (Pi-hole/DNS — not yet deployed).
   Two-tier storage. **Corrected 2026-08-30:** there is no *spare* TP-Link
   router. The TP-Link AX3000 is `AncientGlade`, active on the wall (WAN
   `172.16.141.4` → LAN `192.168.0.0/24`), and it supports Address
   Reservation. The only spare router is a GL.iNet GL-SFT1200 "Opal" (Wi-Fi 5,
   3× gigabit ports, OpenWrt-based). See
   [`router-recommendations.md`](./router-recommendations.md).
3. **Jellyfin consolidates on Hearth.** `hosts/Tawa/jellyfin.nix` will be
   removed from Tawa's imports (deliberate, coordinated change — not a parity
   violation).
4. **Media never lives on the NVMe** (238 GB is too small). NVMe = OS, Nix
   store, service state, Jellyfin metadata + transcode cache. HDD = media
   library + local archives.
5. **NixOS modules over Docker** for every service.
6. **Secrets:** Bitwarden Pro (and/or GitHub) as the human vault. See H5 for
   how that reaches the host — sops-nix is the delivery mechanism, because a
   vault alone cannot decrypt secrets at activation time.
7. **Tailscale** for remote streaming and the special website. No WAN port
   forwarding, ever.
8. **Updates:** automatic remote-dev deployment wanted ("something strong"),
   but **no unsupervised switching of shared files on `main`** — guardrails in
   H7. Builds may run on-box (after freeing NVMe space) or on a stronger host
   with only the switch happening on Hearth.
9. **Acquisition: seedbox-first.** Local downloads allowed only through a VPN.
   Zero local seeding regardless of path.

## Round 2 (2026-08-21 PM)

10. **USB topology:** one high-quality **powered USB hub with UASP** plugs into
    the **USB-C port** (best bandwidth; Surface Connect handles charging),
    hosting the HDD and the server-rack fans (fans on the hub's power rail, not
    a data port; PSU must cover HDD spin-up + fans). The **USB-A port stays
    free** as the recovery/expansion port (keyboard for console rescue
    post-headless, or a gigabit ethernet adapter later).
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
    [`router-recommendations.md`](./router-recommendations.md).
14. **Jellyfin migration:** **fresh start** on Hearth — no `/var/lib/jellyfin`
    state copy from Tawa; only media files transfer.

## Round 3 (2026-08-21 eve)

15. **Wired NIC:** a separate **USB-A gigabit ethernet adapter** (to buy) — the
    hub keeps all its ports for storage/fans; USB-A stops being the rescue port
    once the machine is wired, which is fine post-H0 (SSH is the recovery path
    by then).
16. **Public web presence:** a **serverless webapp on Vercel (or similar) at
    `wiztow.org`**; parts of the intranet exposed as subdomains, e.g.
    **`tv.wizt.org`** for the home media surface. H6 re-scoped around this.
17. **Idle behavior (verified in config):** Hearth never suspends on idle —
    `hypridle` only locks (300 s) and turns the display off (600 s); logind's
    `IdleAction` is at its default of ignore. The only suspend trigger is **lid
    close while on battery**. Confirmed streaming works lid-closed on AC. The
    sole remaining H4 policy choice is what to do on battery.
18. **GiGstreem has no DHCP reservations.** Interim H1 pins
    **172.16.141.38/24** on Hearth's existing NetworkManager `GiGstreem`
    profile (PSK stays on-box, not in the flake). Collision risk if Hearth is
    offline and the ISP pool reissues .38 — accepted until the better router /
    wired LAN.
19. **Seedbox: Ultra.cc.** Account and slot ready before H8. Syncthing (or
    rsync/SSH) pulls completed files into `/mnt/cold/share`. Tailnet join vs
    native Syncthing is decided when H8 lands. Zero local seeding still holds.
20. **Agent sessions stay on AncientGlade** (`192.168.0.133`) until remote
    development works (SSH/Tailscale from Go 2). Cursor cannot reach Hearth on
    GiGstreem. TV hosting still requires GiGstreem `172.16.141.38` — flip SSID
    for playback tests, then come back to AncientGlade to continue this agent.
    Fixed by H0-from-elsewhere / H7, not by another LAN hack.

## Round 4 (2026-08-25)

21. **GitOps end state: push-based only.** `hearth-deploy` is the deploy path
    and **comin is cancelled** (supersedes decision 11). Comin implements one
    of the five H7 guardrails; its one real gain — applying changes without
    Tawa awake — is exactly what breaks guardrail 2, because the path filter
    only runs when the pin advances through `hearth-deploy`. Any future puller
    needs that filter enforced server-side on `deploy/hearth` first. Full
    analysis: [`hearth-gitops-decision.md`](./hearth-gitops-decision.md).

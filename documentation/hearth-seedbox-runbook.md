# Ultra.cc seedbox runbook

The **acquisition tier** for Hearth (plan.md decision 19, phase H8). The slot
downloads and seeds; Hearth stores and serves. Those roles never swap —
Hearth's seeding stays at zero, and the slot never serves media to clients.

This file is the reproduce-it-from-scratch runbook. It exists because almost
nothing below is guessable from outside the slot.

Provider: **Ultra.cc**, slot acquired 2026-08-30, configured 2026-08-31.

Identifying values (slot username, server hostname, Syncthing device and
folder IDs) are deliberately **not** written in the clear here — this repo is
public, and a runbook naming the slot URL beside its torrent stack is not a
pairing worth publishing. They are encrypted in
[`secrets/hearth-seedbox.yaml`](../secrets/hearth-seedbox.yaml):

```bash
sops -d secrets/hearth-seedbox.yaml
```

Placeholders below: `<user>`, `<server>`. Nothing consumes this file at
activation time yet — it is a record. The Hearth Syncthing module will be its
first `sops-nix` consumer.

## Ultra.cc Fair Usage — hard constraints

Slots share physical disks between customers. These are policy limits, not
tuning advice; Ultra.cc states that ignorance is not an excuse.

1. **Never point an Rclone directory directly at cloud storage.** It puts
   extreme strain on the slot's disk and *will* cause repeated 24-hour bans on
   cloud storage access. Stage through local disk instead. Nothing in this
   stack uses Rclone — keep it that way.
2. **Keep concurrent downloads to 1-3 on an HDD plan.** There is no enforced
   cap, which is exactly why it must be set explicitly. Configured here as
   qBittorrent → Options → BitTorrent → Torrent Queueing → **max active
   downloads 3**. The checkbox must be ticked or the number does nothing.

Two operations not covered by those rules still generate heavy sustained IO
and should be staged in small batches rather than run all at once:
**hash-checking** a large batch of cross-seeds, and the **initial Syncthing
upload** of existing library content.

## Slot topology — read this before debugging anything

Ultra.cc mixes two deployment styles on one slot, and this is the root of
most connection problems.

| App | Deployment | Reachable at |
|-----|-----------|--------------|
| qBittorrent | **host-native** (`~/bin/qbittorrent-nox`) | `127.0.0.1:<webui-port>` only |
| Radarr, Prowlarr, Bazarr, Syncthing, Sonarr | **Docker containers** (`/app/…`, `-data=/config`, `s6-supervise`) | own network namespace |

Consequences:

- `ss -tlnp` on the host shows **only** qBittorrent's sockets. The
  containerised apps' listeners are invisible there — that absence is normal,
  not a fault.
- A container's `localhost` is itself, so `127.0.0.1` never reaches
  qBittorrent from Radarr or Sonarr.
- The Docker bridge is `docker0` at `172.17.0.1/16`, which is what containers
  see as "the host".
- **Home is bind-mounted 1:1**: the containers see `/home/<user>/…` at the
  same paths the shell does. No `*arr` Remote Path Mapping is needed, and
  hardlinks work across `torrents/` and `library/`.
- You do **not** have the Docker socket. `/usr/bin/docker` exists but returns
  `permission denied` on `/var/run/docker.sock`, so container-level fixes are
  support tickets.

### App URLs and the auth wall

Every app is proxied at `https://<user>.<server>.usbx.me/<app>` — note
**`usbx.me`**, not `ultra.cc`.

Ultra's nginx puts HTTP basic auth in front of each app's **root**, but
**exempts `/api/` paths**. This is the key that makes app-to-app wiring work:

```
GET /radarr/                    → 401 from nginx      (basic-auth wall)
GET /radarr/api/v3/system/status → 401 from Radarr    (wants an API key)
GET /qbittorrent/api/v2/app/version → 403 from qBittorrent (wants a login)
```

Reading *which* component returned the error is the fastest way to tell an
auth wall from an application fault. A 502/503/504 with an Ultra-branded HTML
body means the application itself is down — restart it from UCP → Applications
→ Actions → Restart, then Upgrade & Repair if that does not hold.

## Connectivity rules between apps

**Everything goes over the public proxy URL.** No loopback, no container IPs.

| Link | Form |
|------|------|
| Radarr / Sonarr → qBittorrent | Host `<user>.<server>.usbx.me`, Port `443`, SSL **on**, **URL Base `/qbittorrent`**, WebUI username + password |
| Prowlarr → Radarr / Sonarr | full URLs in both the Prowlarr Server and app Server fields, plus that app's API key |
| Bazarr → Radarr / Sonarr | Address `<user>.<server>.usbx.me`, Port **443**, Base URL `/radarr` or `/sonarr2`, SSL **on**, API key |

Three traps, each of which cost real time:

- **URL Base is behind "Show Advanced Settings"** in Radarr's and Sonarr's
  download-client forms. Without it the request hits `/api/v2/…` at the domain
  root and fails.
- **Bazarr prefills port `7878` / `8989`.** Switching the address without
  changing the port to `443` is the most likely reason one app connects and
  another does not.
- **Container IPs are not a solution.** They are assigned at start time and
  move on restart. The proxy URL is stable; use it.

### Retired: the docker0 relay

Before the URL Base route was found, qBittorrent was bridged to the containers
by a small Python relay on `172.17.0.1:18291`. **It is no longer in use** and
should not be reintroduced — it was an unsupervised background process that
died on logout or reboot and took both `*arr` apps' download client with it,
silently.

If the proxy route ever breaks, the relay is the fallback, but supervise it
(a systemd user unit with `Restart=always`, lingering enabled) rather than
backgrounding it in a shell.

**Never bind qBittorrent's WebUI to `0.0.0.0` or `*`** to solve a reachability
problem. Ultra runs a `stop_pub` watchdog on a five-minute loop
(`~/.config/.stop_pub/qbittorrent/qbt_pub.py`) that appears to stop publicly
exposed qBittorrent instances, and it would also expose the WebUI on the
slot's assigned IP.

## Directory tree

Everything under `/home/<user>/` is one filesystem — that is what makes the
hardlinks work.

```
/home/<user>/
├── torrents/
│   ├── incomplete/        in-progress data
│   └── done/              finished torrents, seeding
│       ├── movies/          qBittorrent category: radarr
│       └── tv/              qBittorrent category: tv-sonarr
├── library/               ← Syncthing shares this to Hearth
│   ├── movies/              Radarr root folder
│   └── tv/                  Sonarr root folder
└── hearth-upload/         ← Syncthing receives from Hearth
```

**The invariant: nothing writes into `library/` except Sonarr and Radarr.**
That is what makes the tree safe to hand to Syncthing — every filename there
is one Jellyfin can parse, and every deletion is one an `*arr` intended.

Sonarr and Radarr import from `torrents/done` and **hardlink** into
`library/`, so a release exists under two names and one set of bytes. The
torrent keeps seeding under its original name while Jellyfin sees a clean one.
Renaming in the library therefore does **not** disturb seeding.

Set the save paths on the **qBittorrent categories**, not just the global
default — a category carries its own save path and silently overrides.

## App set

Installed: **qBittorrent** (+ **qui** web UI), **Prowlarr**, **Radarr**,
**Sonarr**, **Bazarr**, **Syncthing**, **Homarr** (dashboard only, not part of
the pipeline — it holds API keys, so treat it as credential-bearing).

Deliberately excluded, each for a reason:

- **Usenet** (SABnzbd, NZBGet, NZBHydra2) — no provider.
- **Plex ecosystem** (Tautulli, Ombi, Maintainerr, Doplarr) — Hearth serves
  **Jellyfin**.
- **Serving apps** (Airsonic, Navidrome, Kavita, Komga, Calibre,
  Audiobookshelf, Ubooquity) — the library lives on Hearth's COLD volume and
  only Jellyfin serves it.
- **Superseded** — Jackett (use Prowlarr), autodl-irssi (use Autobrr, and only
  if private-tracker race timing demands it), Readarr, SickChill, Medusa.
- **Second `*arr` instances** — those are for separate 4K profiles.
- **FlareSolverr / Byparr** — add reactively when a specific indexer demands
  one, never preemptively.

**Music is unmanaged.** Lidarr was not installed, so `media/music` on Hearth
stays manual.

### Sonarr is installed as "Sonarr2"

The first Sonarr install failed with a Docker name conflict —
`sonarr-technowizard` already existed as a stopped orphan from an earlier
attempt, and the slot has no Docker socket access to clear it. Installing the
**Sonarr2** app worked, because it uses a different container name.

So the only Sonarr runs at `/sonarr2` and must be wired as such everywhere
(Prowlarr, Bazarr). It is **not** a second instance in any meaningful sense.
The `sonarr-technowizard` name stays burned until a support ticket clears it,
which also means a genuine second instance is unavailable.

## App configuration

**qBittorrent** — Options → Downloads: default save path
`/home/<user>/torrents/done`, ☑ keep incomplete in
`/home/<user>/torrents/incomplete`. Options → BitTorrent: ☑ Torrent Queueing,
max active downloads **3**. Leave max active *uploads* high — seeding is the
point of the slot; it is download IO that hurts disk neighbours.

**Sonarr / Radarr** — Root folders `/home/<user>/library/tv` and
`/home/<user>/library/movies`. Settings → Media Management → **Show Advanced
Settings** → Importing → ☑ **Use Hard Links instead of Copy**. Sonarr:
☑ Rename Episodes (off by default; Jellyfin matches clean names far more
reliably than scene names). Download client category `tv-sonarr` / `radarr`,
**Remove Completed off** so seeding survives import.

**Prowlarr** — Settings → Apps, one entry per `*arr`. Indexers are configured
here **once** and pushed out; leave the `*arr` apps' own Indexers pages empty.

**Bazarr** — one entry per `*arr`. Its `.srt` sidecars land inside `library/`
and sync to Hearth with the media, which is the durable fix for Hearth's
first-play caption delay (see the header of `hosts/Hearth/jellyfin.nix`). That
demotes `hearth-extract-sidecars` to a backfill tool for titles Bazarr finds
no subtitles for.

## Syncthing

Two **unidirectional** folders, deliberately not one bidirectional one.

| Folder | Slot side | Hearth side | Direction |
|--------|-----------|-------------|-----------|
| `hearth-library` | `/home/<user>/library` — **Send Only** | `/mnt/cold/share` — **Receive Only** | acquisitions down |
| `hearth-upload` | `/home/<user>/hearth-upload` — **Receive Only** + File Versioning | `/mnt/cold/upload` — **Send Only** | existing COLD content up |

Folder IDs must match on both sides; the real IDs are in
`secrets/hearth-seedbox.yaml`.

**No tailnet join and no VPN.** Ultra.cc offers no Tailscale app and Syncthing
does not need one: device-ID auth over its own TLS, with hole-punching and
relay fallback, crosses Hearth's double NAT. Do not install Ultra's WireGuard
for this.

### Why two folders and not one

A single Send & Receive folder makes deletions round-trip. When Hearth's
routing step moves a file out of `/mnt/cold/share` into `/mnt/cold/media/`,
Syncthing propagates that deletion up to `library/`, where Sonarr and Radarr
then mark the episode missing and re-grab it — an unbounded re-download loop
against a shared-disk quota. Splitting the directions removes the whole class
of problem: the `*arr`-managed library is never writable by Hearth.

### Deletion semantics

`/mnt/cold/share` is a **landing zone, never the library.** Slot-side
deletions propagate down, so Hearth must **hardlink** out of `share/` into
`/mnt/cold/media/{movies,tv}` — never move. Moving files out of a Receive Only
folder leaves it permanently out of sync, where the only remedy Syncthing
offers is "Revert Local Changes", which re-downloads everything.

Because Bazarr adds subtitles hours or days after the video lands, that
routing job must run on a schedule, not once per file.

### Sync is not backup

`hearth-upload` only becomes a real offsite copy with **File Versioning**
enabled on the slot side (Trash Can, or Simple keeping 3-5 versions).
Without it, a deletion or corruption on Hearth propagates up and destroys the
remote copy. Watch `.stversions` for quota growth.

## Cross-seeding existing COLD content

Syncthing puts files on the slot; it does **not** make them seed. Seeding
needs a `.torrent` whose piece hashes match the files exactly — names, folder
structure, sizes.

This works only for content still in **original release naming**. Anything
Sonarr or Radarr has already renamed will not match a tracker's torrent.

1. Let Syncthing finish pushing a release into `hearth-upload/`.
2. Add the `.torrent` in qBittorrent with **Save Path** set to the directory
   *containing* the release folder — not the folder itself. Off-by-one here is
   the usual reason a cross-seed shows 0%.
3. Leave hash checking **on** and let it verify to 100%.
4. Give it a category neither Sonarr nor Radarr watches, so they do not try to
   import your own library back into itself.

Batch this. Hash-checking is sustained read IO, which is the Fair Usage axis
Ultra actually watches.

## Verification

After any import, confirm the hardlink rather than assuming it:

```bash
find ~/library ~/torrents/done -type f \( -name '*.mkv' -o -name '*.mp4' \) \
  -printf '%n  %i  %p\n' | sort -k2
```

Expect **pairs**: two lines sharing an inode, both showing link count `2` —
one scene-named under `torrents/done`, one clean-named under `library/`.

Link count `1` on both means the import **copied**, doubling disk against
quota. Check the advanced hardlink toggle and that both paths are under
`/home/<user>/`.

```bash
du -sh ~/torrents ~/library
```

Run together, `du` credits a shared inode once, so the two figures should sum
to roughly one copy of the content rather than two.

## Known failure modes

**Content downloaded straight into `library/`** — scene names, link count `1`,
`torrents/done` empty. Means the download bypassed the pipeline (usually a
category save path pointing at the library, or a torrent added before the
tree existed). Recover by setting the category's save path correctly, then
qBittorrent → right-click → **Set Location** to `torrents/done/<type>` and
letting the `*arr` import it properly. Do not rename by hand — the point is
for the `*arr` to own the import.

**Series folder keeps the scene release name** after a manual import, because
the `*arr` adopted the existing folder as the series path. Fix in the series'
**Edit → Path**; it is a rename within one filesystem, so inodes survive and
seeding is unaffected.

**Install fails with a Docker name conflict.** An orphaned container from a
previous attempt. No socket access to clear it, so it is a support ticket —
or install the numbered variant of the app, as was done for Sonarr2.

## Do not

- Add Rclone, in any configuration.
- Bind qBittorrent's WebUI to `0.0.0.0` or `*`.
- Reintroduce the unsupervised `docker0` relay.
- Let anything but Sonarr and Radarr write into `library/`.
- Point Syncthing at `torrents/` — it would ship scene-named files to Hearth
  and double-count the still-seeding copy against quota.
- Enable **Remove Completed** in any `*arr` download client.
- Run a torrent client on Hearth, or seed from Hearth, in any path. The
  `common/vpn-vortix.nix` FrootVPN stack is workstation-oriented and must
  never land on the media host.

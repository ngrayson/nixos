# H8 ingest pipeline — seedbox app set and the two-folder Syncthing design

Reasoning moved out of [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md) H8 on
2026-09-01, when that file was restructured into an index so it would stop
outgrowing Conveyor's 32,000-character overview cap for the `hearth` tag.
**Nothing here is superseded.** plan.md keeps H8's binding rules — hardlink
never move, `share/` is a landing zone, no local seeding, `ignorePerms` on
COLD, no Ultra WireGuard; this file keeps the reasoning behind the shape.

## Why the sync leg needs no tailnet join and no VPN

This resolved open question 2 on 2026-08-30. Ultra.cc's app catalogue offers no
Tailscale app, and Syncthing does not need one: it authenticates by device ID
over its own TLS, and hole-punching with relay fallback already covers Hearth's
double NAT. Installing Ultra's WireGuard for this would add a moving part that
buys nothing.

## Why the organized tree is shared, not the torrent directory

Sonarr and Radarr run **on the seedbox** and hardlink from `~/torrents/done`
into `~/library`; only `~/library` is shared with Syncthing. Sharing the raw
torrent directory would send scene-named files to Hearth and would double-count
the still-seeding copy against Ultra's disk quota.

## Why two unidirectional folders instead of one bidirectional (as-built 2026-08-31)

- `hearth-library`: slot `~/library` **Send Only** → Hearth `/mnt/cold/share`
  **Receive Only**, carrying acquisitions down.
- `hearth-upload`: Hearth `/mnt/cold/upload` **Send Only** → slot
  `~/hearth-upload` **Receive Only**, with File Versioning, carrying existing
  COLD content up as a versioned offsite copy.

A single Send & Receive folder would round-trip deletions. Hearth's routing
step moving a file out of `share/` would delete it from the slot's `~/library`,
and Sonarr/Radarr would then mark the episode missing and re-grab it in an
unbounded loop. This is the concrete reason behind plan.md's "hardlink out,
never move" rule.

Because files arrive already sorted into `movies/` and `tv/`, the tag-routing
step shrinks to a move rather than a classifier.

## The app set, chosen 2026-08-30

Syncthing, qBittorrent (+ qui), Prowlarr, Sonarr, Radarr, Bazarr.

Deliberately excluded: no usenet stack (no provider), no Plex-ecosystem tools
(Hearth serves Jellyfin), no second `*arr` instances, and no serving apps — the
library lives on COLD and only Hearth serves it. Autobrr goes in only if
private-tracker race timing demands it; FlareSolverr or Byparr only when a
specific indexer asks for one.

## Subtitles

Bazarr writes real `.srt` sidecars upstream, which sync over alongside the
media. That is the durable fix for the first-play caption delay, and it demotes
`hearth-extract-sidecars` to a fallback for titles Bazarr finds no subtitles
for. New arrivals still call `hearth-extract-sidecars --one <file>` after the
ingest step so they get sidecars without waiting for a library-wide pass.

## The local fallback path

A VPN-piped local download is a fallback only: reuse the repo's existing VPN
stack (`common/vpn-vortix.nix`, stunnel/FrootVPN — the server-safe subset) or a
dedicated namespace so torrent traffic cannot leak, with upload hard-capped at
zero. Zero local seeding holds in both paths.

## Slot runbook

[`hearth-seedbox-runbook.md`](./hearth-seedbox-runbook.md) carries Ultra.cc's
Fair Usage limits, the host-native/container split that dictates how the apps
reach each other, the directory tree, and the verification commands.
Identifying values (slot username, hostname, Syncthing device and folder IDs)
stay out of the clear in this public repo; they are encrypted in
`secrets/hearth-seedbox.yaml` (`sops -d` to read).

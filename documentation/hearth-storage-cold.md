# COLD storage — the USB link fix and the Jellyfin casing saga

Narrative moved out of [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md) H2 on
2026-09-01, when that file was restructured into an index so it would stop
outgrowing Conveyor's 32,000-character overview cap for the `hearth` tag.
**Nothing here is superseded.** plan.md keeps H2's binding rules — do not
format COLD, `chmod` returns `EPERM`, hardlinks work, ntfs-3g is
case-sensitive, `.mblink` carries no trailing newline; this file keeps the
stories that produced them.

## The USB link was the bottleneck (fixed 2026-08-25 PM)

The enclosure used to negotiate **480 Mb/s / USB 2.10** behind a USB2.1 hub
(`usb3/3-4/3-4.1`), capping reads at 40 MB/s — the cause of the caption delay
under H3. Moved to the laptop's USB-C port on a SuperSpeed-rated cable, it now
enumerates at **10 Gb/s** (`usb2/2-1/2-1.1`) and cold-reads at **197 MB/s**
(platter limit — the link is no longer the bottleneck).

Two gotchas for next time:

- The first C-to-C cable tried was **charge-only**. It enumerated USB2 with
  zero SuperSpeed link and produced no error anywhere.
- The enclosure **does not re-attach on plug-in alone** — it needs a power
  cycle after any cable move.

The GenesysLogic hub that shows up alongside COLD is *inside the enclosure*; it
power-cycles with the drive.

## Why `chmod` on COLD kept breaking Syncthing

The volume is mounted `uid=0 gid=989 umask=0002` (`hosts/Hearth/host.nix`), so
ownership and permission bits come from the *mount options* — every file is
`root:jellyfin` regardless of who wrote it, and `chmod(2)` returns `EPERM`.

This has cost real time twice. Syncthing's default permission-syncing made
every pull into `/mnt/cold/share` die with `handling dir (setting
permissions): chmod ...: operation not permitted`, aborting the whole folder
cycle with exponential backoff while the files sat as `.syncthing.*.tmp` and
were never renamed into place — with the folder still reporting `idle`, which
reads like a slow peer rather than an error. The fix is `ignorePerms` on both
folders (`hosts/Hearth/syncthing.nix`).

Group membership is how processes get write access instead: `wiz` is in
`jellyfin` (`hosts/Hearth/jellyfin.nix`), which is what makes `umask=0002`
writable.

## Hardlinks do work (verified 2026-08-31)

`ln` across directories gives link count 2 and a shared inode, and removing the
source leaves the target intact at count 1. This is what lets H8 ingest
hardlink out of `share/` into `media/` for free instead of copying, and it is
why moving is never necessary. Both paths must be on `/mnt/cold`; a link across
filesystems fails.

Neither this nor the `chmod` behaviour is visible to `hearth-deploy build`.
Filesystem semantics on COLD can only be validated by activating and watching
the service.

## Casing has three sides, and renaming the disk only fixes one

ntfs-3g mounts COLD case-sensitively, so `music` and `Music` are two different
directories. The archive shipped as `Music` and was renamed to lowercase to
match the tmpfiles rule. A mismatch leaves the populated tree unscanned beside
an empty twin that Jellyfin logs as "inaccessible or empty, skipping".

The library path also lives in **server state, outside Nix**, at
`/var/lib/jellyfin/root/default/Music/{music.mblink,options.xml}`. Both sides
have to change whenever the directory moves, followed by a `jellyfin` restart
and a rescan.

`music.mblink` must hold the path with **no trailing newline** (21 bytes for
`/mnt/cold/media/music`). Jellyfin does not trim it; a newline becomes part of
the lookup and reads as the same "inaccessible or empty" skip as a case
mismatch. Write it with `printf`, not `echo`, or edit the folder in
Dashboard → Libraries.

`hearth-healthcheck.sh` now fails the deploy if any library `.mblink` ends in a
newline, names a directory that does not exist, or disagrees with its
`options.xml` **in either direction** — a stale `<Path>` a rename left behind
fails too, since Jellyfin keeps scanning it. A missing library root is a
failure rather than a skipped check, so the probe cannot quietly disappear if
Jellyfin's layout moves. An empty music shelf should never again survive a
green switch.

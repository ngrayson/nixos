# Hearth caption first-play latency — investigation record

Historical detail moved out of [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md)
H3 on 2026-08-31, when that file outgrew Conveyor's 32,000-character overview
cap for the `hearth` tag. **Nothing here is superseded** — the measurements and
the inventory below are still the evidence behind H3's conclusions. plan.md
keeps the conclusions and the rules; this file keeps the numbers.

Related: Conveyor investigation card
`investigate-sidecar-subtitle-pre-extraction-for-hearth-s-lib`
([PR #55](https://github.com/ngrayson/nixos/pull/55)) and the shipped one-shot
`hearth-extract-sidecars` ([PR #58](https://github.com/ngrayson/nixos/pull/58),
`hosts/Hearth/extract-sidecars.nix`).

- **Captions lag on first play — COLD's USB2 link was why (fixed).**
  Embedded ASS/SRT tracks are extracted on demand with
  `ffmpeg -i <file> -map <n> -c:s copy`, which demuxes the *whole* container;
  video direct-plays immediately, so the picture runs uncaptioned until that
  full-file read finishes. The wait is roughly `filesize / read speed`.
  Measured 2026-08-25 AM at the old **40 MB/s** (USB2 link): 15s for a
  ~700 MB episode, 35s for 1.4 GB, observed as bad as 152s with two
  concurrent extractions. After the port/cable fix (H2) COLD cold-reads at
  **197 MB/s**.
  - ~~Fastest real win: move COLD off the USB2.1 hub~~ — **done 2026-08-25**,
    see H2.
  - **Residual delay, measured 2026-08-25 evening (post-USB fix).** Cold
    extract of Tongari ep 02 (1.44 GB ASS): **7.4s**. Live Jellyfin first-play
    of Gachiakuta 11 (1.45 GB, never cached): **8.0s**
    (`SubtitleEncoder` 20:28:53→20:29:00). Cold extract of LOTR Fellowship
    (5.80 GB, three `subrip` tracks in one ffmpeg): **31s**. Font dumps are
    a separate, client-driven tail: 14 serial `-dump_attachment` calls on
    Tongari took **3.8s** (~0.25s each). The 5s "good enough, do nothing"
    bar is **not** met across the board.
  - **Sidecar font question (measured).** Jellyfin 10.11 skips
    `ExtractAllExtractableSubtitles` for external `.ass`/`.srt` (not `.mks`).
    A manually placed `Title.eng.default.ass` next to Gachiakuta 12 was
    picked up on item Refresh as `IsExternal` index 0 / default, and
    `Stream.ass` returned in **107ms** with **no** `SubtitleEncoder` line.
    Sidecars do **not** skip the font tail if the client then asks for
    attachments: `GET /Videos/.../Attachments/{n}` still runs
    `AttachmentExtractor` against the MKV (~0.76s per font). The size-
    proportional wait is the extract; fonts stay iff the client fetches them.
  - **Inventory (2026-08-25):** 1336 video files under
    `media/{tv,movies}` (1.14 TB). 1278 have at least one subtitle track
    (1952 tracks: 1598 ASS, 195 subrip, 144 PGS, 13 DVD, 2 mov_text);
    7939 embedded font/other attachments. Three prototype sidecars were
    left next to Gachiakuta 11/12 and Tongari 02. A full sequential pass
    at 197 MB/s is **~1.6h** (all files) / **~1.5h** (files with subs).
  - **Recommendation: no service; one-shot signed off and shipped.**
    `hearth-extract-sidecars` (hosts/Hearth/extract-sidecars.nix) is the
    manual pass — idempotent, text tracks only, no timer. New arrivals
    call the same binary via H8 ingest (`--one`), not a timer.
  - Not a fix: `EnableSubtitleExtraction` only *permits* on-the-fly
    extraction; disabling it removes captions rather than speeding them up.
    Jellyfin 10.11 has no pre-extract-during-scan option.

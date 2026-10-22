"""Merge Hearth's private ICS feeds into /run/hearth-intranet/calendar.ics.

Run by hearth-intranet-calendar.service (hosts/Hearth/intranet-calendar.nix),
which passes the sops feed list in HEARTH_CALENDAR_FEEDS_FILE. Kept as a file
rather than an inline heredoc so tests/hearth-calendar/ can import body_lines.
The feed URLs are credentials: never log or print them.
"""

import json, os, sys, urllib.error, urllib.request

OUT = "/run/hearth-intranet/calendar.ics"


def log(msg):
    # Never include the URL: it is the credential.
    print(msg, file=sys.stderr, flush=True)


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "hearth-intranet-calendar"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8", errors="replace")


def escape(value):
    # ICS text escaping for the values we inject ourselves.
    return (
        str(value)
        .replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\n", " ")
    )


def body_lines(text, name, calendar_id):
    """Inner lines of one VCALENDAR, with each VEVENT tagged by feed.

    BEGIN:VEVENT is always its own unfolded line, so inserting straight
    after it is safe even when the feed folds long properties.
    """
    keep = []
    depth = 0
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        # Keep trailing spaces: RFC 5545 folds can split right after a
        # space, so "SUMMARY:Dinner with " + " Bob" must stay
        # "Dinner with Bob" once ical.js unfolds it. Only blank lines go.
        line = raw
        if not line.strip():
            continue
        if line.startswith("BEGIN:VCALENDAR"):
            depth += 1
            continue
        if line.startswith("END:VCALENDAR"):
            depth -= 1
            continue
        if depth < 1:
            continue
        keep.append(line)
        if line.startswith("BEGIN:VEVENT"):
            if name:
                keep.append("X-HEARTH-CALENDAR:" + escape(name))
            if calendar_id:
                keep.append("X-HEARTH-CALENDAR-ID:" + escape(calendar_id))
    return keep


def main():
    out = OUT
    feeds_path = os.environ.get("HEARTH_CALENDAR_FEEDS_FILE", "")
    feeds = json.load(open(feeds_path, encoding="utf-8")) if feeds_path else []

    if not feeds:
        # No feed configured: drop a stale file so the widget shows nothing.
        try:
            os.remove(out)
        except FileNotFoundError:
            pass
        sys.exit(0)

    merged = []
    ok = 0
    for index, feed in enumerate(feeds):
        label = feed.get("name") or f"feed {index + 1}"
        try:
            text = fetch(feed["url"])
        except urllib.error.HTTPError as exc:
            log(f"{label}: HTTP {exc.code}")
            continue
        except Exception as exc:
            log(f"{label}: {type(exc).__name__}")
            continue
        if "BEGIN:VEVENT" not in text and "BEGIN:VCALENDAR" not in text:
            log(f"{label}: response is not an ICS document")
            continue
        lines = body_lines(text, feed.get("name") or "", feed.get("calendarId") or "")
        log(f"{label}: {sum(1 for line in lines if line.startswith('BEGIN:VEVENT'))} events")
        merged.extend(lines)
        ok += 1

    # Fail open: one bad feed must not wipe the good ones, and a total
    # failure leaves the previous file in place rather than blanking the card.
    if not ok:
        log(f"no feed fetched ({len(feeds)} configured); keeping the previous file")
        sys.exit(0)

    doc = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//hearth//intranet//EN"]
    doc.extend(merged)
    doc.append("END:VCALENDAR")

    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\r\n".join(doc))
        fh.write("\r\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, out)
    log(f"wrote {ok}/{len(feeds)} feeds")


if __name__ == "__main__":
    main()

"""Deciding what `hearth-disk` should do next, given COLD's probed state.

Kept apart from any screen so the decision is a pure function over
`hearth-disk status` rows and can be tested without SSH or a running app.
"""

from __future__ import annotations

from typing import Literal

DiskAction = Literal["park", "resume", "unclear"]

# Wording for the menu entry, so the operator reads what will happen rather
# than the rule that picks it.
ACTION_LABELS: dict[DiskAction, str] = {
    "park": "Disk — Park COLD",
    "resume": "Disk — Mount COLD & resume Jellyfin",
    "unclear": "Disk — COLD state unclear",
}
PENDING_LABEL = "Disk — checking COLD…"

PARK_CONFIRM_MESSAGE = (
    "This stops Jellyfin, unmounts /mnt/cold, and powers off the COLD enclosure. Continue?"
)
RESUME_CONFIRM_MESSAGE = "This mounts /mnt/cold and starts Jellyfin. Continue?"


def _row(rows: list[tuple[bool, str]], *prefixes: str) -> bool:
    """Whether the first row whose message starts with one of `prefixes` passed.

    Missing rows count as failed, so an unreadable status never looks healthy.
    """
    for passed, message in rows:
        if message.startswith(prefixes):
            return passed
    return False


def decide_disk_action(rows: list[tuple[bool, str]]) -> DiskAction:
    """Pick park, resume, or neither from `hearth-disk status` output.

    Rows are found by their message text from `probe_status` in
    hosts/Hearth/disk.nix, never by position: `hearth-disk` prints `[ok]` rows
    to stdout and `[fail]` rows to stderr, so once the two streams are joined
    every ok row comes before every fail row and positions no longer match
    the probe order. Anything that is not cleanly "mounted and serving" or
    "plugged in but idle" is reported as unclear rather than guessed at — a
    park chosen on a misread would stop Jellyfin and unmount the disk.
    """
    device_present = _row(rows, "device ", "COLD device missing")
    mounted = _row(rows, "/mnt/cold is mounted", "/mnt/cold is not mounted")
    jellyfin_active = _row(rows, "Jellyfin is active", "Jellyfin is not active")

    if mounted and jellyfin_active:
        return "park"
    if device_present and not mounted:
        return "resume"
    return "unclear"


def confirm_message(action: DiskAction) -> str:
    return PARK_CONFIRM_MESSAGE if action == "park" else RESUME_CONFIRM_MESSAGE


def render_rows(rows: list[tuple[bool, str]], fallback: str = "") -> str:
    """Format ok/fail rows for display, as the old disk screen did."""
    if not rows:
        return fallback.strip() or "(no output)"
    return "\n".join(
        f"[green]ok[/green]   {message}" if passed else f"[red]fail[/red] {message}"
        for passed, message in rows
    )

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


def decide_disk_action(rows: list[tuple[bool, str]]) -> DiskAction:
    """Pick park, resume, or neither from `hearth-disk status` output.

    Row order comes from `probe_status` in hosts/Hearth/disk.nix: device
    present, mounted, jellyfin active, jellyfin health. Anything that is not
    cleanly "mounted and serving" or "plugged in but idle" is reported as
    unclear rather than guessed at — a park chosen on a misread would stop
    Jellyfin and unmount the disk.
    """
    device_present = rows[0][0] if len(rows) > 0 else False
    mounted = rows[1][0] if len(rows) > 1 else False
    jellyfin_active = rows[2][0] if len(rows) > 2 else False

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

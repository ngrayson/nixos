"""Shared output parsing and value rendering for hearth-tui screens."""

from __future__ import annotations

import json

from rich.markup import escape


def temp_colour(celsius: float) -> str:
    """Severity colour for a temperature: green < 60°C, yellow 60-79°C, red ≥ 80°C."""
    if celsius >= 80:
        return "red"
    if celsius >= 60:
        return "yellow"
    return "green"


def usage_colour(pct: float) -> str:
    """Severity colour for a fill percentage: green < 80%, yellow 80-89%, red ≥ 90%."""
    if pct >= 90:
        return "red"
    if pct >= 80:
        return "yellow"
    return "green"


def render_bar(fraction: float, colour: str, width: int = 16) -> str:
    """A fixed-width Rich-markup bar: colour-filled █ cells, dim ░ for the rest.

    `fraction` is clamped to 0..1 so a sensor glitch (negative, or >100%)
    renders as an empty/full bar instead of raising.
    """
    fraction = min(1.0, max(0.0, fraction))
    filled = round(fraction * width)
    return f"[{colour}]{'█' * filled}[/{colour}][dim]{'░' * (width - filled)}[/dim]"


def parse_ok_fail_lines(text: str) -> list[tuple[bool, str]]:
    """Split `[ok]`/`[fail]`-prefixed lines into (passed, message) pairs.

    scripts/hearth-healthcheck.sh and `hearth-disk status` both emit this
    format (`ok()`/`fail()` helpers in each script) — this is shared by every
    screen that runs one of those scripts verbatim rather than re-deriving
    its checks.
    """
    rows: list[tuple[bool, str]] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[ok]"):
            rows.append((True, stripped[len("[ok]") :].strip()))
        elif stripped.startswith("[fail]"):
            rows.append((False, stripped[len("[fail]") :].strip()))
    return rows


def snapshot_text(returncode: int, stdout: str, stderr: str) -> str:
    """Render `restic snapshots --json` for the backup panel.

    The exit code decides first: restic writes its errors to stderr (as an
    `exit_error` JSON object with --json) and leaves stdout empty, so an
    unchecked failure used to parse as `[]` and read "(no snapshots yet)" —
    a parked COLD or a broken repository looked like a fresh, empty one.
    """
    if returncode != 0:
        for line in reversed((stderr or "").splitlines()):
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict) and obj.get("message_type") == "exit_error":
                msg = obj.get("message") or "repository unavailable — is COLD mounted?"
                return f"[yellow]{escape(msg.strip())}[/yellow]"
        last = next((l for l in reversed((stderr or "").splitlines()) if l.strip()), "")
        return f"[red]restic failed (exit {returncode}): {escape(last.strip()) or 'no error output'}[/red]"

    try:
        parsed = json.loads(stdout) if stdout.strip() else []
    except json.JSONDecodeError:
        return f"[red]{escape((stdout + stderr).strip()) or '(no output)'}[/red]"
    if not isinstance(parsed, list):
        return f"[red]Unexpected restic output: {escape(stdout.strip())}[/red]"
    if not parsed:
        return "(no snapshots yet)"
    return "\n".join(
        f"{snap.get('short_id', '?')}  {snap.get('time', '?')[:19]}  "
        + ",".join(snap.get("tags", []) or [])
        for snap in parsed
    )

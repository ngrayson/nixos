"""Shared output parsing and value rendering for hearth-tui screens."""

from __future__ import annotations


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

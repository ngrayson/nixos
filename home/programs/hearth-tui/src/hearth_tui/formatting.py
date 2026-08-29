"""Shared output parsing for hearth-tui screens."""

from __future__ import annotations


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

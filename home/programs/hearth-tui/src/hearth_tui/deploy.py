"""Local (non-SSH) runner for scripts/hearth-deploy.sh.

hearth-deploy.sh manages its own SSH connection to Hearth internally (its own
ControlMaster, `ssh_hearth()` calls) — this module runs the script as a local
subprocess and must never route through `hearth_tui.ssh`.
"""

from __future__ import annotations

import asyncio
import os
from collections.abc import AsyncIterator
from pathlib import Path

SCRIPT = (
    Path(os.environ.get("NIXOS_DIR", "~/.config/nixos")).expanduser()
    / "scripts"
    / "hearth-deploy.sh"
)


async def stream_deploy(action: str) -> AsyncIterator[str]:
    """Run `bash hearth-deploy.sh <action> --yes` locally, yielding decoded lines.

    `--yes` skips the script's own confirmations so it never blocks waiting on
    a TTY prompt Textual has captured — confirmation for switch/boot instead
    happens in a Textual modal before this is called.

    stdin is DEVNULL, not inherited. The script's `ssh_hearth()` runs `ssh`
    without `-n`, and ssh reads stdin by default, so an inherited terminal is
    read out from under Textual and the operator's keystrokes disappear into
    the remote command instead of reaching the app. DEVNULL also turns any
    prompt that does survive `--yes` into an immediate EOF, so it fails
    visibly rather than hanging in silence.
    """
    proc = await asyncio.create_subprocess_exec(
        "bash",
        str(SCRIPT),
        action,
        "--yes",
        stdin=asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    assert proc.stdout is not None
    async for raw_line in proc.stdout:
        yield raw_line.decode(errors="replace").rstrip("\n")
    await proc.wait()

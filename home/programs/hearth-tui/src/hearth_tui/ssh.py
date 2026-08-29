"""Shared SSH runner for hearth-tui.

Every remote call goes through the `Host hearth` alias defined in
`~/.ssh/config.d/hearth` (home/programs/ssh-hearth.nix) — OpenSSH on port 22,
the same trust boundary scripts/hearth-deploy.sh and the `hearth-unmount`
alias already use. Never hardcode Hearth's LAN IP or the Tailscale MagicDNS
name here.
"""

from __future__ import annotations

import asyncio
import subprocess
from collections.abc import AsyncIterator
from pathlib import Path

HOST = "hearth"


def run(*args: str, sudo: bool = False, timeout: float = 15) -> subprocess.CompletedProcess:
    """Run a short-lived command on Hearth and capture its output."""
    cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", HOST]
    if sudo:
        cmd.append("sudo")
    cmd.extend(args)
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


async def stream(*args: str, sudo: bool = False) -> AsyncIterator[str]:
    """Run a long-lived command on Hearth, yielding decoded stdout lines as they arrive."""
    cmd = ["ssh", "-o", "BatchMode=yes", HOST]
    if sudo:
        cmd.append("sudo")
    cmd.extend(args)
    proc = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT
    )
    assert proc.stdout is not None
    async for raw_line in proc.stdout:
        yield raw_line.decode(errors="replace").rstrip("\n")
    await proc.wait()


def run_script(
    local_script_path: Path, sudo: bool = True, timeout: float = 30
) -> subprocess.CompletedProcess:
    """Feed a local script's contents to `ssh hearth [sudo] bash -s`.

    Mirrors scripts/hearth-deploy.sh's run_healthcheck
    (`ssh_hearth -o BatchMode=yes sudo bash -s <"$script"`) so callers can run
    an existing repo script verbatim on Hearth instead of re-deriving its
    logic in Python.
    """
    cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", HOST]
    if sudo:
        cmd.append("sudo")
    cmd.extend(["bash", "-s"])
    with local_script_path.open("rb") as stdin:
        return subprocess.run(
            cmd, stdin=stdin, capture_output=True, text=True, timeout=timeout
        )

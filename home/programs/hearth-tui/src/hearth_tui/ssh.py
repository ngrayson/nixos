"""Shared SSH runner for hearth-tui.

Every remote call goes through the `Host hearth` alias defined in
`~/.ssh/config.d/hearth` (home/programs/ssh-hearth.nix) — OpenSSH on port 22,
the same trust boundary scripts/hearth-deploy.sh and the `hearth-unmount`
alias already use. Never hardcode Hearth's LAN IP or the Tailscale MagicDNS
name here.
"""

from __future__ import annotations

import asyncio
import shlex
import subprocess
from collections.abc import AsyncIterator
from pathlib import Path

HOST = "hearth"


class SshError(Exception):
    """A remote call could not be completed — timed out, or ssh itself failed.

    Every helper below raises this instead of leaking `subprocess.TimeoutExpired`
    or `OSError`, so callers running inside a Textual worker can catch one type
    and render the failure. An uncaught exception in a worker takes the whole
    app down, which is exactly what a flaky hop used to do.
    """


def _remote_command(args: tuple[str, ...], sudo: bool) -> str:
    """Quote args into one shell-safe string.

    ssh joins argv elements after the hostname with plain spaces before
    handing them to the remote shell, with no re-quoting — so passing
    e.g. ("bash", "-c", "ip -br addr; ...") as separate argv elements lets
    the remote shell re-split the script on its embedded spaces instead of
    treating it as one token. Pre-quoting into a single argv element avoids
    that.
    """
    remote = ["sudo", *args] if sudo else list(args)
    return shlex.join(remote)


def run(*args: str, sudo: bool = False, timeout: float = 15) -> subprocess.CompletedProcess:
    """Run a short-lived command on Hearth and capture its output."""
    cmd = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=8",
        HOST,
        _remote_command(args, sudo),
    ]
    try:
        # stdin=DEVNULL, never inherited: ssh reads stdin by default, so under
        # the TUI it would consume the terminal Textual is reading and swallow
        # the operator's keystrokes.
        return subprocess.run(
            cmd,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise SshError(f"{HOST}: timed out after {timeout}s running {args[0]}") from exc
    except OSError as exc:
        raise SshError(f"{HOST}: {exc}") from exc


async def stream(*args: str, sudo: bool = False) -> AsyncIterator[str]:
    """Run a long-lived command on Hearth, yielding decoded stdout lines as they arrive.

    A caller that stops iterating early (e.g. a Textual worker cancelled to
    switch to a different tail) must not leave `ssh` and the remote command
    (a `journalctl -f`, say) running orphaned — the `finally` below terminates
    the local ssh client on early exit, which tears down the remote side too.
    """
    cmd = ["ssh", "-o", "BatchMode=yes", HOST, _remote_command(args, sudo)]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
    except OSError as exc:
        raise SshError(f"{HOST}: {exc}") from exc
    assert proc.stdout is not None
    try:
        async for raw_line in proc.stdout:
            yield raw_line.decode(errors="replace").rstrip("\n")
        await proc.wait()
    except OSError as exc:
        # asyncio.CancelledError is a BaseException, not an OSError, so a
        # worker cancelled to switch tails still unwinds through `finally`
        # untouched — only real I/O failures become SshError.
        raise SshError(f"{HOST}: {exc}") from exc
    finally:
        if proc.returncode is None:
            proc.terminate()
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
    try:
        with local_script_path.open("rb") as stdin:
            return subprocess.run(
                cmd, stdin=stdin, capture_output=True, text=True, timeout=timeout
            )
    except subprocess.TimeoutExpired as exc:
        raise SshError(
            f"{HOST}: timed out after {timeout}s running {local_script_path.name}"
        ) from exc
    except OSError as exc:
        raise SshError(f"{HOST}: {exc}") from exc

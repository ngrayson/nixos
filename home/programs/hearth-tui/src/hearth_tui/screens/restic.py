"""Restic screen: read-only view of `restic-backups-hearth`'s last run and
snapshot list (hosts/Hearth/restic.nix). Restoring is a deliberate manual
runbook (hosts/Hearth/restic.md) — this screen never offers restore/prune/
forget actions.
"""

from __future__ import annotations

import json
import re

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import VerticalScroll
from textual.screen import Screen
from textual.widgets import Footer, Header, Static

from hearth_tui import ssh

UNIT = "restic-backups-hearth.service"


def _parse_unit_config(cat_output: str) -> tuple[str | None, str | None, str | None]:
    """Extract (restic_bin, repository, password_file) from `systemctl cat` output.

    Discovered live from the running unit rather than hardcoded, since the
    nix store paths embedded in its ExecStart/Environment lines change across
    rebuilds (see this card's plan step 1).
    """
    repo = None
    password_file = None
    restic_bin = None
    for line in cat_output.splitlines():
        stripped = line.strip()
        match = re.match(r'Environment="RESTIC_REPOSITORY=(.*)"$', stripped)
        if match:
            repo = match.group(1)
            continue
        match = re.match(r'Environment="RESTIC_PASSWORD_FILE=(.*)"$', stripped)
        if match:
            password_file = match.group(1)
            continue
        match = re.match(r"ExecStart=(\S*/restic)\b", stripped)
        if match and restic_bin is None:
            restic_bin = match.group(1)
    return restic_bin, repo, password_file


class ResticScreen(Screen):
    """Read-only restic backup status + snapshot list."""

    BINDINGS = [
        Binding("r", "refresh", "Refresh"),
        Binding("escape", "app.pop_screen", "Back"),
    ]

    def compose(self) -> ComposeResult:
        yield Header()
        with VerticalScroll():
            yield Static("Loading…", id="restic-run")
            yield Static("", id="restic-snapshots")
        yield Footer()

    def on_mount(self) -> None:
        self.action_refresh()

    def action_refresh(self) -> None:
        self.query_one("#restic-run", Static).update("Refreshing…")
        self.query_one("#restic-snapshots", Static).update("")
        self.run_refresh()

    @work(thread=True)
    def run_refresh(self) -> None:
        run_result = ssh.run(
            "systemctl",
            "show",
            UNIT,
            "-p",
            "ActiveState,Result,ExecMainStartTimestamp,ExecMainExitTimestamp",
            timeout=15,
        )
        run_text = (run_result.stdout or run_result.stderr or "(no output)").strip()
        self.app.call_from_thread(
            self.query_one("#restic-run", Static).update, f"[b]last run[/b]\n{run_text}"
        )

        cat_result = ssh.run("systemctl", "cat", UNIT, sudo=True, timeout=15)
        restic_bin, repo, password_file = _parse_unit_config(cat_result.stdout)
        if not (restic_bin and repo and password_file):
            self.app.call_from_thread(
                self.query_one("#restic-snapshots", Static).update,
                "[red]Could not discover the restic binary/repository/password-file "
                f"from {UNIT} — check `ssh hearth sudo systemctl cat {UNIT}`.[/red]",
            )
            return

        snap_result = ssh.run(
            restic_bin,
            "-r",
            repo,
            "--password-file",
            password_file,
            "snapshots",
            "--json",
            sudo=True,
            timeout=30,
        )
        self._render_snapshots(snap_result.stdout, snap_result.stderr)

    def _render_snapshots(self, stdout: str, stderr: str) -> None:
        try:
            parsed = json.loads(stdout) if stdout.strip() else []
        except json.JSONDecodeError:
            text = f"[red]{(stdout + stderr).strip() or '(no output)'}[/red]"
            self.app.call_from_thread(self.query_one("#restic-snapshots", Static).update, text)
            return

        if isinstance(parsed, dict) and parsed.get("message_type") == "exit_error":
            # e.g. the repo path under /mnt/cold is unreachable — COLD is parked.
            text = f"[yellow]{parsed.get('message', 'repository unavailable — is COLD mounted?')}[/yellow]"
        elif isinstance(parsed, list):
            if not parsed:
                text = "(no snapshots yet)"
            else:
                lines = [
                    f"{snap.get('short_id', '?')}  {snap.get('time', '?')[:19]}  "
                    + ",".join(snap.get("tags", []) or [])
                    for snap in parsed
                ]
                text = "[b]snapshots[/b]\n" + "\n".join(lines)
        else:
            text = f"[red]Unexpected restic output: {stdout.strip()}[/red]"
        self.app.call_from_thread(self.query_one("#restic-snapshots", Static).update, text)

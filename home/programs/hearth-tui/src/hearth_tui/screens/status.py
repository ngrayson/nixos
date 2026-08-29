"""Status screen: runs scripts/hearth-healthcheck.sh verbatim over SSH plus a
raw network panel, instead of re-deriving Hearth's health probes in Python.
"""

from __future__ import annotations

import os
from pathlib import Path

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import VerticalScroll
from textual.screen import Screen
from textual.widgets import Footer, Header, Static

from hearth_tui import ssh
from hearth_tui.formatting import parse_ok_fail_lines


def _nixos_dir() -> Path:
    """Same NIXOS_DIR convention as scripts/hearth-deploy.sh (default ~/.config/nixos)."""
    return Path(os.environ.get("NIXOS_DIR", "~/.config/nixos")).expanduser()


class StatusScreen(Screen):
    """Health + network status for Hearth."""

    BINDINGS = [
        Binding("r", "refresh_status", "Refresh"),
        Binding("escape", "app.pop_screen", "Back"),
    ]

    def compose(self) -> ComposeResult:
        yield Header()
        with VerticalScroll():
            yield Static("Loading…", id="healthcheck")
            yield Static("", id="network")
        yield Footer()

    def on_mount(self) -> None:
        self.action_refresh_status()

    def action_refresh_status(self) -> None:
        self.query_one("#healthcheck", Static).update("Refreshing…")
        self.query_one("#network", Static).update("")
        self.run_healthcheck()

    @work(thread=True)
    def run_healthcheck(self) -> None:
        script = _nixos_dir() / "scripts" / "hearth-healthcheck.sh"
        if not script.is_file():
            self.app.call_from_thread(
                self.query_one("#healthcheck", Static).update,
                f"[red]Missing {script} — set NIXOS_DIR if the flake checkout lives elsewhere.[/red]",
            )
            return

        health_result = ssh.run_script(script, sudo=True, timeout=30)
        health_text = health_result.stdout + health_result.stderr
        rows = parse_ok_fail_lines(health_text)
        if rows:
            lines = [
                f"[green]ok[/green]   {message}" if passed else f"[red]fail[/red] {message}"
                for passed, message in rows
            ]
        else:
            lines = [health_text.strip() or "(no output)"]
        self.app.call_from_thread(self.query_one("#healthcheck", Static).update, "\n".join(lines))

        network_result = ssh.run(
            "bash",
            "-c",
            "ip -br addr; echo ---; ip -br link; echo ---; ip route show default",
            timeout=15,
        )
        network_text = network_result.stdout or network_result.stderr or "(no output)"
        self.app.call_from_thread(
            self.query_one("#network", Static).update, f"[b]network[/b]\n{network_text}"
        )

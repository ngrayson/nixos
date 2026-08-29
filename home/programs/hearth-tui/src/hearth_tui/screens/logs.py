"""Logs screen: live-tails journalctl for Hearth's key services via
hearth_tui.ssh.stream, so checking logs doesn't need a separate
`ssh hearth journalctl -u ... -f` in another terminal.
"""

from __future__ import annotations

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, VerticalScroll
from textual.screen import Screen
from textual.widgets import Footer, Header, ListItem, ListView, RichLog, Static

from hearth_tui import ssh

UNITS: list[str] = ["jellyfin", "caddy", "restic-backups-hearth", "tailscaled", "sshd"]

# Workers in this group are exclusive — starting a new tail cancels the
# previous one automatically, so switching units never interleaves output.
TAIL_GROUP = "logs-tail"


class LogsScreen(Screen):
    """Live journalctl tail for one of Hearth's key services at a time."""

    BINDINGS = [
        Binding("x", "stop_stream", "Stop"),
        Binding("escape", "app.pop_screen", "Back"),
    ]

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal():
            yield ListView(
                *(ListItem(Static(unit), name=unit) for unit in UNITS),
                id="log-units",
            )
            with VerticalScroll():
                yield RichLog(id="log-output", wrap=True, markup=False, max_lines=2000)
        yield Footer()

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        unit = event.item.name
        if unit is None:
            return
        log = self.query_one("#log-output", RichLog)
        log.clear()
        log.write(f"-- following {unit} --")
        self.run_tail(unit)

    def action_stop_stream(self) -> None:
        self.app.workers.cancel_group(self, TAIL_GROUP)

    @work(exclusive=True, group=TAIL_GROUP)
    async def run_tail(self, unit: str) -> None:
        log = self.query_one("#log-output", RichLog)
        async for line in ssh.stream("journalctl", "-u", unit, "-f", "-n", "100"):
            log.write(line)

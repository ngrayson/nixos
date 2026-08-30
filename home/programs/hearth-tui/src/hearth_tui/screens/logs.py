"""Logs screen: live-tails journalctl for Hearth's key services via
hearth_tui.ssh.stream, so checking logs doesn't need a separate
`ssh hearth journalctl -u ... -f` in another terminal.
"""

from __future__ import annotations

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, ListView, RichLog

from hearth_tui import ssh
from hearth_tui.widgets import MenuList

UNITS: list[str] = ["jellyfin", "caddy", "restic-backups-hearth", "tailscaled", "sshd"]

# Workers in this group are exclusive — starting a new tail cancels the
# previous one automatically, so switching units never interleaves output.
TAIL_GROUP = "logs-tail"


class LogsScreen(Screen):
    """Live journalctl tail for one of Hearth's key services at a time."""

    DEFAULT_CSS = """
    LogsScreen {
        border: round $primary;
    }
    LogsScreen #log-output {
        border: round $primary;
        padding: 0 1;
        height: 1fr;
    }
    LogsScreen #log-units {
        height: auto;
    }
    """

    BINDINGS = [
        Binding("x", "stop_stream", "Stop"),
        Binding("escape", "app.pop_screen", "Back"),
    ]

    def compose(self) -> ComposeResult:
        yield Header()
        yield RichLog(id="log-output", wrap=True, markup=False, max_lines=2000)
        yield MenuList([(unit, unit) for unit in UNITS], id="log-units")
        yield Footer()

    def on_mount(self) -> None:
        # Mirrors MainMenu/DeployScreen: focus the menu so arrow keys drive
        # unit selection immediately instead of landing elsewhere.
        self.query_one("#log-output", RichLog).border_title = "logs"
        menu = self.query_one(MenuList)
        menu.border_title = "units"
        menu.focus()

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        unit = event.item.name
        if unit is None:
            return
        log = self.query_one("#log-output", RichLog)
        log.clear()
        log.border_title = f"following {unit}"
        self.run_tail(unit)

    def action_stop_stream(self) -> None:
        self.app.workers.cancel_group(self, TAIL_GROUP)

    @work(exclusive=True, group=TAIL_GROUP)
    async def run_tail(self, unit: str) -> None:
        log = self.query_one("#log-output", RichLog)
        try:
            async for line in ssh.stream("journalctl", "-u", unit, "-f", "-n", "100"):
                log.write(line)
        except ssh.SshError as exc:
            # markup=False (journal lines are arbitrary text), so no [red] here.
            log.write(f"tail stopped: {exc}")

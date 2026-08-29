"""Disk screen: wraps `hearth-disk status/resume/park` (hosts/Hearth/disk.nix)
instead of re-deriving its checks, so parking/resuming COLD no longer needs a
raw `ssh hearth sudo hearth-disk ...` call or the `hearth-unmount` alias.
"""

from __future__ import annotations

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import VerticalScroll
from textual.screen import Screen
from textual.widgets import Footer, Header, RichLog, Static

from hearth_tui import ssh
from hearth_tui.formatting import parse_ok_fail_lines
from hearth_tui.modals import ConfirmModal

PARK_CONFIRM_MESSAGE = (
    "This stops Jellyfin, unmounts /mnt/cold, and powers off the COLD enclosure. Continue?"
)


class DiskScreen(Screen):
    """COLD disk status, resume, and park."""

    BINDINGS = [
        Binding("s", "refresh_status", "Status"),
        Binding("u", "resume", "Resume"),
        Binding("p", "park", "Park"),
        Binding("escape", "app.pop_screen", "Back"),
    ]

    def compose(self) -> ComposeResult:
        yield Header()
        with VerticalScroll():
            yield Static("Loading…", id="disk-status")
            yield RichLog(id="disk-log", wrap=True, markup=True)
        yield Footer()

    def on_mount(self) -> None:
        self.action_refresh_status()

    def action_refresh_status(self) -> None:
        self.query_one("#disk-status", Static).update("Refreshing…")
        self.run_status()

    def action_resume(self) -> None:
        self.query_one("#disk-log", RichLog).write("[b]resume[/b]")
        self.run_resume()

    def action_park(self) -> None:
        self.app.push_screen(ConfirmModal(PARK_CONFIRM_MESSAGE), self._on_park_confirmed)

    def _on_park_confirmed(self, confirmed: bool) -> None:
        if not confirmed:
            return
        self.query_one("#disk-log", RichLog).write("[b]park[/b]")
        self.run_park()

    @work(thread=True)
    def run_status(self) -> None:
        result = ssh.run("hearth-disk", "status", sudo=True, timeout=15)
        text = result.stdout + result.stderr
        rows = parse_ok_fail_lines(text)
        if rows:
            lines = [
                f"[green]ok[/green]   {message}" if passed else f"[red]fail[/red] {message}"
                for passed, message in rows
            ]
        else:
            lines = [text.strip() or "(no output)"]
        self.app.call_from_thread(self.query_one("#disk-status", Static).update, "\n".join(lines))

    @work
    async def run_resume(self) -> None:
        log = self.query_one("#disk-log", RichLog)
        async for line in ssh.stream("hearth-disk", "resume", sudo=True):
            log.write(line)
        self.action_refresh_status()

    @work
    async def run_park(self) -> None:
        log = self.query_one("#disk-log", RichLog)
        async for line in ssh.stream("hearth-disk", "park", sudo=True):
            if "safe to unplug" in line:
                log.write(f"[b yellow]{line}[/b yellow]")
            else:
                log.write(line)
        self.action_refresh_status()

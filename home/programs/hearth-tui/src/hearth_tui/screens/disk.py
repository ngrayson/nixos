"""Disk screen: runs the correct `hearth-disk` action for COLD's current
state (hosts/Hearth/disk.nix) instead of asking the operator to pick.

Status itself lives on the home screen as `hearth_tui.widgets.DiskStatusWidget`
— this screen is action-only.
"""

from __future__ import annotations

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import VerticalScroll
from textual.screen import Screen
from textual.widgets import Footer, Header, RichLog

from hearth_tui import ssh
from hearth_tui.formatting import parse_ok_fail_lines
from hearth_tui.modals import ConfirmModal

PARK_CONFIRM_MESSAGE = (
    "This stops Jellyfin, unmounts /mnt/cold, and powers off the COLD enclosure. Continue?"
)


class DiskScreen(Screen):
    """Parks COLD if it's mounted with Jellyfin active, resumes it if it's
    plugged in but unmounted. Any other combination is left for the operator
    to sort out manually — never guessed.
    """

    BINDINGS = [Binding("escape", "app.pop_screen", "Back")]

    def compose(self) -> ComposeResult:
        yield Header()
        with VerticalScroll():
            yield RichLog(id="disk-log", wrap=True, markup=True)
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#disk-log", RichLog).write("[b]checking COLD status…[/b]")
        self.decide_action()

    @work(thread=True)
    def decide_action(self) -> None:
        try:
            result = ssh.run("hearth-disk", "status", sudo=True, timeout=15)
        except ssh.SshError as exc:
            # Never guess an action from a status we could not read — a park
            # decided on missing evidence would stop Jellyfin and unmount COLD.
            self.app.call_from_thread(
                self.query_one("#disk-log", RichLog).write,
                f"[red]Could not read COLD status: {exc}[/red]",
            )
            return
        text = result.stdout + result.stderr
        rows = parse_ok_fail_lines(text)
        # hearth-disk status's probe order (hosts/Hearth/disk.nix probe_status):
        # device present, mounted, jellyfin active, jellyfin health.
        device_present = rows[0][0] if len(rows) > 0 else False
        mounted = rows[1][0] if len(rows) > 1 else False
        jellyfin_active = rows[2][0] if len(rows) > 2 else False

        if mounted and jellyfin_active:
            self.app.call_from_thread(self._confirm_park)
        elif device_present and not mounted:
            self.app.call_from_thread(self._start_stream, "resume")
        else:
            if rows:
                lines = [
                    f"[green]ok[/green]   {message}" if passed else f"[red]fail[/red] {message}"
                    for passed, message in rows
                ]
            else:
                lines = [text.strip() or "(no output)"]
            self.app.call_from_thread(
                self.query_one("#disk-log", RichLog).write,
                "[yellow]Not a clean park-or-resume state — check status "
                "and act manually:[/yellow]\n" + "\n".join(lines),
            )

    def _confirm_park(self) -> None:
        self.app.push_screen(ConfirmModal(PARK_CONFIRM_MESSAGE), self._on_park_confirmed)

    def _on_park_confirmed(self, confirmed: bool | None) -> None:
        if not confirmed:
            self.query_one("#disk-log", RichLog).write("park cancelled")
            return
        self._start_stream("park")

    def _start_stream(self, action: str) -> None:
        self.query_one("#disk-log", RichLog).write(f"[b]{action}[/b]")
        self.run_action_stream(action)

    @work
    async def run_action_stream(self, action: str) -> None:
        log = self.query_one("#disk-log", RichLog)
        try:
            async for line in ssh.stream("hearth-disk", action, sudo=True):
                if "safe to unplug" in line:
                    log.write(f"[b yellow]{line}[/b yellow]")
                else:
                    log.write(line)
        except ssh.SshError as exc:
            log.write(f"[red]{action} interrupted: {exc}[/red]")
            log.write(
                "[yellow]COLD may be mid-transition — check `hearth-disk status` "
                "before unplugging anything.[/yellow]"
            )

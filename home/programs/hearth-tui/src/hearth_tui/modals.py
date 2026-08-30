"""Shared modal dialogs for hearth-tui."""

from __future__ import annotations

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Button, RichLog, Static

from hearth_tui import ssh
from hearth_tui.disk_action import DiskAction, confirm_message, render_rows


class ConfirmModal(ModalScreen[bool]):
    """Yes/No confirmation dialog. Dismisses with True (yes) or False (no/cancel)."""

    BINDINGS = [
        Binding("y", "confirm", "Yes"),
        Binding("n", "cancel", "No"),
        Binding("escape", "cancel", "Cancel", show=False),
    ]

    def __init__(self, message: str) -> None:
        super().__init__()
        self._message = message

    def compose(self) -> ComposeResult:
        with Vertical(id="confirm-dialog"):
            yield Static(self._message, id="confirm-message")
            yield Button("Yes", id="confirm-yes", variant="error")
            yield Button("No", id="confirm-no", variant="primary")

    def on_mount(self) -> None:
        # Without focus a Button ignores enter/space, which left the mouse as
        # the only way to answer. Focus No, not Yes: this dialog guards
        # deploy switch/boot, so a stray enter must not activate a live server.
        self.query_one("#confirm-no", Button).focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "confirm-yes")

    def action_confirm(self) -> None:
        self.dismiss(True)

    def action_cancel(self) -> None:
        self.dismiss(False)


class DiskActionModal(ModalScreen[None]):
    """Confirm a COLD park/resume, then show it running, without leaving home.

    Three phases in one dialog: confirm, running, done. Cancelling is refused
    while the action runs — `ssh.stream` kills the remote command when the
    caller stops iterating, and a park interrupted midway would leave Jellyfin
    stopped with the disk still mounted.
    """

    DEFAULT_CSS = """
    DiskActionModal {
        align: center middle;
    }
    DiskActionModal #disk-dialog {
        border: round $primary;
        background: $surface;
        padding: 1 2;
        width: 70%;
        max-width: 90;
        height: auto;
        max-height: 80%;
    }
    DiskActionModal #disk-message {
        margin-bottom: 1;
    }
    DiskActionModal #disk-log {
        height: auto;
        max-height: 16;
        margin-bottom: 1;
    }
    DiskActionModal Horizontal {
        height: auto;
    }
    DiskActionModal Button {
        margin-right: 2;
    }
    """

    BINDINGS = [
        Binding("y", "confirm", "Yes"),
        Binding("enter", "confirm", "Yes", show=False),
        Binding("n", "cancel", "No"),
        Binding("escape", "cancel", "Close", show=False),
    ]

    def __init__(self, action: DiskAction, rows: list[tuple[bool, str]]) -> None:
        super().__init__()
        self._action = action
        self._rows = rows
        # "confirm" waits on the operator, "running" refuses to be dismissed,
        # "done" accepts any key to close.
        self._phase = "done" if action == "unclear" else "confirm"

    def compose(self) -> ComposeResult:
        with Vertical(id="disk-dialog"):
            if self._action == "unclear":
                message = (
                    "[yellow]Not a clean park-or-resume state — check status and act "
                    "manually:[/yellow]\n" + render_rows(self._rows)
                )
            else:
                message = confirm_message(self._action)
            yield Static(message, id="disk-message")
            yield RichLog(id="disk-log", wrap=True, markup=True)
            with Horizontal(id="disk-choices"):
                yield Button("Yes", id="disk-yes", variant="error")
                yield Button("No", id="disk-no", variant="primary")
            yield Button("Close", id="disk-close", variant="primary")

    def on_mount(self) -> None:
        self.query_one("#disk-log", RichLog).display = False
        if self._action == "unclear":
            self.query_one("#disk-choices", Horizontal).display = False
            self.query_one("#disk-close", Button).focus()
        else:
            self.query_one("#disk-close", Button).display = False
            self.query_one("#disk-yes", Button).focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "disk-yes":
            self.action_confirm()
        else:
            self.action_cancel()

    def action_confirm(self) -> None:
        if self._phase == "done":
            self.dismiss(None)
            return
        if self._phase != "confirm":
            return
        self._phase = "running"
        self.query_one("#disk-choices", Horizontal).display = False
        log = self.query_one("#disk-log", RichLog)
        log.display = True
        log.write(f"[b]{self._action}[/b]")
        self.run_action_stream(self._action)

    def action_cancel(self) -> None:
        # Deliberately inert mid-run: see the class docstring.
        if self._phase == "running":
            return
        self.dismiss(None)

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
                "[yellow]COLD may be mid-transition — check the disk status "
                "before unplugging anything.[/yellow]"
            )
        finally:
            self._finish()

    def _finish(self) -> None:
        self._phase = "done"
        close = self.query_one("#disk-close", Button)
        close.display = True
        close.focus()

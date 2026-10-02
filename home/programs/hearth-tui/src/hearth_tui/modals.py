"""Shared modal dialogs for hearth-tui."""

from __future__ import annotations

from rich.markup import escape
from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Button, Input, RichLog, Static

from hearth_tui import ssh
from hearth_tui.disk_action import DiskAction, confirm_message, render_rows

# Shared dialog-box look for every modal, mirroring widgets.WIDGET_BORDER_CSS
# for panels — width/max-width stay per-modal since content sizes differ.
DIALOG_CSS = """
border: round $primary;
background: $surface;
padding: 1 2;
height: auto;
"""


class ConfirmModal(ModalScreen[bool]):
    """Yes/No confirmation dialog. Dismisses with True (yes) or False (no/cancel)."""

    DEFAULT_CSS = f"""
    ConfirmModal {{
        align: center middle;
    }}
    ConfirmModal #confirm-dialog {{
        {DIALOG_CSS}
        width: 60%;
        max-width: 70;
    }}
    ConfirmModal #confirm-message {{
        margin-bottom: 1;
    }}
    ConfirmModal #confirm-choices {{
        height: auto;
    }}
    ConfirmModal Button {{
        margin-right: 2;
    }}
    """

    BINDINGS = [
        Binding("y", "confirm", "Yes"),
        Binding("n", "cancel", "No"),
        Binding("escape", "cancel", "Cancel", show=False),
        Binding("left", "app.focus_previous", show=False),
        Binding("right", "app.focus_next", show=False),
    ]

    def __init__(self, message: str) -> None:
        super().__init__()
        self._message = message

    def compose(self) -> ComposeResult:
        with Vertical(id="confirm-dialog"):
            yield Static(self._message, id="confirm-message")
            with Horizontal(id="confirm-choices"):
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

    DEFAULT_CSS = f"""
    DiskActionModal {{
        align: center middle;
    }}
    DiskActionModal #disk-dialog {{
        {DIALOG_CSS}
        width: 70%;
        max-width: 90;
        max-height: 80%;
    }}
    DiskActionModal #disk-message {{
        margin-bottom: 1;
    }}
    DiskActionModal #disk-log {{
        height: auto;
        max-height: 16;
        margin-bottom: 1;
    }}
    DiskActionModal Horizontal {{
        height: auto;
    }}
    DiskActionModal Button {{
        margin-right: 2;
    }}
    """

    BINDINGS = [
        Binding("y", "confirm", "Yes"),
        Binding("enter", "confirm", "Yes", show=False),
        Binding("n", "cancel", "No"),
        Binding("escape", "cancel", "Close", show=False),
        Binding("left", "app.focus_previous", show=False),
        Binding("right", "app.focus_next", show=False),
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


class ScryTaskModal(ModalScreen[None]):
    """File one task in Nick's Tasks (Notion) via `scry-task` on Hearth.

    Same input → running → done shape as DiskActionModal. The grammar and the
    Notion schema live once, in pkgs/scry/task.mjs; this dialog only hands the
    typed line over ssh and shows the URL (or the error) it gets back. The
    Notion token never leaves Hearth.
    """

    DEFAULT_CSS = f"""
    ScryTaskModal {{
        align: center middle;
    }}
    ScryTaskModal #scry-dialog {{
        {DIALOG_CSS}
        width: 70%;
        max-width: 90;
    }}
    ScryTaskModal #scry-hint {{
        margin-bottom: 1;
    }}
    ScryTaskModal #scry-log {{
        height: auto;
        max-height: 8;
        margin: 1 0;
    }}
    """

    BINDINGS = [
        Binding("escape", "cancel", "Close", show=False),
    ]

    def __init__(self) -> None:
        super().__init__()
        self._phase = "input"

    def compose(self) -> ComposeResult:
        with Vertical(id="scry-dialog"):
            yield Static(
                "[b]Scry — file a task in Nick's Tasks (Notion)[/b]\n"
                "[dim]p0-p3  #area  due:2026-10-04|oct 4|fri|+3d|tomorrow  @agent|@collab[/dim]",
                id="scry-hint",
            )
            yield Input(placeholder="Replace COLD drive p2 #hearth due:fri", id="scry-text")
            yield RichLog(id="scry-log", wrap=True, markup=True)
            yield Button("Close", id="scry-close", variant="primary")

    def on_mount(self) -> None:
        self.query_one("#scry-log", RichLog).display = False
        self.query_one("#scry-close", Button).display = False
        self.query_one("#scry-text", Input).focus()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        text = event.value.strip()
        if not text or self._phase != "input":
            return
        self._phase = "running"
        event.input.disabled = True
        log = self.query_one("#scry-log", RichLog)
        log.display = True
        log.write("[b]filing…[/b]")
        self.file_task(text)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.action_cancel()

    def action_cancel(self) -> None:
        # Inert while filing: the row may already exist, so leaving before the
        # URL comes back would hide whether it did.
        if self._phase == "running":
            return
        self.dismiss(None)

    @work(thread=True)
    def file_task(self, text: str) -> None:
        log = self.query_one("#scry-log", RichLog)
        try:
            # ssh._remote_command shlex-joins the text into one argv element,
            # so quotes, `#` and `@` reach scry-task intact.
            result = ssh.run("scry-task", text, sudo=True, timeout=30)
            if result.returncode == 0:
                msg = f"[green]filed[/green] {result.stdout.strip()}"
            else:
                err = (result.stderr or result.stdout).strip() or "scry-task failed"
                msg = f"[red]{escape(err)}[/red]"
        except ssh.SshError as exc:
            msg = f"[red]{escape(str(exc))}[/red]"
        self.app.call_from_thread(log.write, msg)
        self.app.call_from_thread(self._finish)

    def _finish(self) -> None:
        self._phase = "done"
        close = self.query_one("#scry-close", Button)
        close.display = True
        close.focus()

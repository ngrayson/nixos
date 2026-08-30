"""Deploy screen: runs scripts/hearth-deploy.sh subcommands (doctor/health/
build/dry-activate/switch/boot) locally with live streamed output. A thin
front end for the script's own guardrails (shared-path refusal, hardware-dirty
warning, rollback-on-health-fail messaging, Discord notify) — never a
reimplementation of them.
"""

from __future__ import annotations

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, ListView, RichLog

from hearth_tui import deploy
from hearth_tui.modals import ConfirmModal
from hearth_tui.widgets import MenuList

ACTIONS: list[tuple[str, str]] = [
    ("doctor", "Doctor — probe SSH, sudo, trusted-users"),
    ("health", "Health — post-activate probes"),
    ("build", "Build — build only, no copy/activate"),
    ("dry-activate", "Dry-activate — build, copy, show diff"),
    ("switch", "Switch — build, copy, activate, health"),
    ("boot", "Boot — build, copy, set next boot generation"),
]

ACTIVATION_ACTIONS = {"switch", "boot"}


class DeployScreen(Screen):
    """Runs hearth-deploy.sh subcommands with live streamed output."""

    DEFAULT_CSS = """
    DeployScreen {
        border: round $primary;
    }
    DeployScreen #deploy-log {
        border: round $primary;
        padding: 0 1;
        height: 1fr;
    }
    DeployScreen #deploy-actions {
        height: auto;
    }
    """

    BINDINGS = [Binding("escape", "app.pop_screen", "Back")]

    def compose(self) -> ComposeResult:
        yield Header()
        yield RichLog(id="deploy-log", wrap=True, markup=True)
        yield MenuList(ACTIONS, id="deploy-actions")
        yield Footer()

    def on_mount(self) -> None:
        # Mirrors MainMenu.on_mount: without an explicit focus, arrow keys
        # would land on whichever widget Textual picks first rather than
        # driving the actions menu.
        self.query_one("#deploy-log", RichLog).border_title = "rebuild output"
        self.query_one(MenuList).focus()

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        action = event.item.name
        if action is None:
            return
        if action in ACTIVATION_ACTIONS:
            self.app.push_screen(
                ConfirmModal(f"Run '{action}' on Hearth? This activates on the live server."),
                lambda confirmed: self._on_confirmed(action, confirmed),
            )
        else:
            self._run_action(action)

    def _on_confirmed(self, action: str, confirmed: bool | None) -> None:
        if not confirmed:
            return
        self._run_action(action)

    def _run_action(self, action: str) -> None:
        self.query_one("#deploy-log", RichLog).write(f"[b]{action}[/b]")
        self.run_deploy_action(action)

    @work
    async def run_deploy_action(self, action: str) -> None:
        log = self.query_one("#deploy-log", RichLog)
        if not deploy.SCRIPT.is_file():
            log.write(
                f"[red]Missing {deploy.SCRIPT} — set NIXOS_DIR if the flake "
                "checkout lives elsewhere.[/red]"
            )
            return
        async for line in deploy.stream_deploy(action):
            log.write(line)

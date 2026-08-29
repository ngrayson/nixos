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
from textual.containers import Horizontal, VerticalScroll
from textual.screen import Screen
from textual.widgets import Footer, Header, ListItem, ListView, RichLog, Static

from hearth_tui import deploy
from hearth_tui.modals import ConfirmModal

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

    BINDINGS = [Binding("escape", "app.pop_screen", "Back")]

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal():
            yield ListView(
                *(ListItem(Static(label), name=name) for name, label in ACTIONS),
                id="deploy-actions",
            )
            with VerticalScroll():
                yield RichLog(id="deploy-log", wrap=True, markup=True)
        yield Footer()

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

    def _on_confirmed(self, action: str, confirmed: bool) -> None:
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

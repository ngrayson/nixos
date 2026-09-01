"""Deploy screen: runs scripts/hearth-deploy.sh subcommands (status/doctor/
health/build/dry-activate/switch/boot) locally with live streamed output. A
thin front end for the script's own guardrails (shared-path refusal,
hardware-dirty warning, rollback-on-health-fail messaging, Discord notify) —
never a reimplementation of them.
"""

from __future__ import annotations

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal
from textual.screen import Screen
from textual.widgets import Footer, Header, Label, ListView, RichLog, Switch

from hearth_tui import deploy
from hearth_tui.modals import ConfirmModal
from hearth_tui.widgets import MenuList

# Labels track `hearth-deploy.sh`'s own usage() text, so the TUI cannot drift
# from what the script says it does. `ssh` is deliberately absent: it opens an
# interactive shell, which does not fit this screen's streamed-log model.
ACTIONS: list[tuple[str, str]] = [
    ("status", "Status — connection + flake status"),
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
    DeployScreen #deploy-flags {
        border: round $primary;
        padding: 0 1;
        height: auto;
    }
    DeployScreen #deploy-flags Label {
        padding: 1 2 0 0;
    }
    """

    BINDINGS = [Binding("escape", "app.pop_screen", "Back")]

    def compose(self) -> ComposeResult:
        yield Header()
        yield RichLog(id="deploy-log", wrap=True, markup=True)
        # Toggles rather than a modal per run: the flags are orthogonal to the
        # action, so asking every time would be friction, and a switch that is
        # visibly on is more discoverable than a prompt.
        with Horizontal(id="deploy-flags"):
            yield Switch(id="flag-no-stage")
            yield Label("--no-stage  (do not offer to git-add untracked flake inputs)")
            yield Switch(id="flag-from-checkout")
            yield Label("--from-checkout  (activate the builder worktree)")
        yield MenuList(ACTIONS, id="deploy-actions")
        yield Footer()

    def on_mount(self) -> None:
        # Mirrors MainMenu.on_mount: without an explicit focus, arrow keys
        # would land on whichever widget Textual picks first rather than
        # driving the actions menu.
        self.query_one("#deploy-log", RichLog).border_title = "rebuild output"
        self.query_one("#deploy-flags", Horizontal).border_title = "flags"
        menu = self.query_one(MenuList)
        menu.border_title = "actions"
        menu.focus()

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

    def _flags(self) -> tuple[bool, bool]:
        """Current toggle state, read when the action fires rather than cached."""
        return (
            self.query_one("#flag-no-stage", Switch).value,
            self.query_one("#flag-from-checkout", Switch).value,
        )

    def _run_action(self, action: str) -> None:
        no_stage, from_checkout = self._flags()
        shown = " ".join(
            [action]
            + (["--no-stage"] if no_stage else [])
            + (["--from-checkout"] if from_checkout else [])
        )
        self.query_one("#deploy-log", RichLog).write(f"[b]{shown}[/b]")
        self.run_deploy_action(action, no_stage, from_checkout)

    @work
    async def run_deploy_action(
        self, action: str, no_stage: bool = False, from_checkout: bool = False
    ) -> None:
        log = self.query_one("#deploy-log", RichLog)
        if not deploy.SCRIPT.is_file():
            log.write(
                f"[red]Missing {deploy.SCRIPT} — set NIXOS_DIR if the flake "
                "checkout lives elsewhere.[/red]"
            )
            return
        async for line in deploy.stream_deploy(
            action, no_stage=no_stage, from_checkout=from_checkout
        ):
            log.write(line)

"""hearth-tui: a terminal dashboard for the Hearth home server.

Wraps the SSH commands already run against Hearth (scripts/hearth-healthcheck.sh,
hearth-disk, scripts/hearth-deploy.sh, restic, journalctl) as Textual screens
instead of re-deriving their logic — see each screen module's docstring.
Run from Tawa/Theseus; talks to Hearth over the `hearth` SSH alias (hearth_tui.ssh).
"""

from __future__ import annotations

import subprocess

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.screen import Screen
from textual.widgets import Footer, Header, ListItem, ListView, Static

from hearth_tui import ssh
from hearth_tui.disk_action import ACTION_LABELS, PENDING_LABEL, DiskAction, decide_disk_action
from hearth_tui.modals import DiskActionModal
from hearth_tui.screens.deploy import DeployScreen
from hearth_tui.screens.logs import LogsScreen
from hearth_tui.widgets import (
    DiskStatusWidget,
    HealthcheckWidget,
    MenuList,
    NetworkWidget,
    ResticRunWidget,
    ResticSnapshotsWidget,
    SystemWidget,
)

# One entry per screen. Children add to this dict and to MENU_ITEMS —
# a one-line change each, per the pack's plan. Status/restic/disk status are
# home-screen widgets, not screens — see hearth_tui.widgets.
SCREENS: dict[str, type[Screen]] = {
    "deploy": DeployScreen,
    "logs": LogsScreen,
}

# (name, label) — display order for the main menu. "disk" is not in SCREENS:
# it opens a modal over the home screen instead, and its label is rewritten
# from live status (see MainMenu.on_disk_status_widget_status_ready).
MENU_ITEMS: list[tuple[str, str]] = [
    ("disk", PENDING_LABEL),
    ("deploy", "Deploy — hearth-deploy.sh actions"),
    ("logs", "Logs — live journalctl tail"),
]


class MainMenu(Screen):
    """Landing screen: glance at status/restic stats, then pick a screen below."""

    DEFAULT_CSS = """
    MainMenu {
        border: round $primary;
    }
    MainMenu #stats > Horizontal {
        height: auto;
    }
    MainMenu #disk-system-col {
        width: 1fr;
        height: auto;
    }
    """

    BINDINGS = [
        Binding("q", "app.quit", "Quit"),
        Binding("r", "refresh_stats", "Refresh"),
    ]

    # Latest probe, kept so selecting the disk entry acts on the same state the
    # label was written from. "unclear" until the first probe lands, so a
    # selection made before then opens the read-only view rather than guessing.
    _disk_action: DiskAction = "unclear"
    _disk_rows: list[tuple[bool, str]] = []

    def compose(self) -> ComposeResult:
        yield Header()
        with VerticalScroll(id="stats"):
            with Horizontal():
                yield HealthcheckWidget()
                with Vertical(id="disk-system-col"):
                    yield DiskStatusWidget()
                    yield SystemWidget()
            yield NetworkWidget()
            with Horizontal():
                yield ResticRunWidget()
                yield ResticSnapshotsWidget()
        yield MenuList(MENU_ITEMS, id="menu")
        yield Footer()

    def on_mount(self) -> None:
        # VerticalScroll is itself focusable (for scrolling with arrow keys);
        # without this, initial focus lands on #stats instead of the menu, so
        # arrow keys would scroll the stats panel rather than move the
        # selection — the menu must stay keyboard-driven regardless of
        # whatever the stats widgets are doing in their refresh workers.
        menu = self.query_one(MenuList)
        menu.border_title = "menu"
        menu.focus()

    def on_screen_resume(self) -> None:
        # Refresh whenever we come back from a pushed screen (e.g. after a
        # disk park/resume), so stale pre-action status doesn't linger.
        self.action_refresh_stats()

    def action_refresh_stats(self) -> None:
        self.query_one(HealthcheckWidget).refresh_data()
        self.query_one(DiskStatusWidget).refresh_data()
        self.query_one(SystemWidget).refresh_data()
        self.query_one(NetworkWidget).refresh_data()
        self.query_one(ResticRunWidget).refresh_data()
        self.query_one(ResticSnapshotsWidget).refresh_data()

    def on_disk_status_widget_status_ready(
        self, event: DiskStatusWidget.StatusReady
    ) -> None:
        """Relabel the disk entry to name the action its state calls for."""
        self._disk_rows = event.rows
        self._disk_action = decide_disk_action(event.rows)
        for item in self.query_one(MenuList).query(ListItem):
            if item.name == "disk":
                item.query_one(Static).update(ACTION_LABELS[self._disk_action])
                break

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        name = event.item.name
        if name == "disk":
            self.app.push_screen(DiskActionModal(self._disk_action, self._disk_rows))
        elif name in SCREENS:
            self.app.push_screen(SCREENS[name]())


class HearthTuiApp(App):
    """Terminal dashboard for Hearth."""

    # Shown by every screen's Header — replaces the Static title the main
    # screen used to render below the Header, which duplicated it.
    TITLE = "hearth-tui"

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("ctrl+s", "shell", "Shell"),
        Binding("b", "btop", "btop"),
    ]

    def on_mount(self) -> None:
        self.theme = "ansi-dark"
        self.push_screen(MainMenu())

    def action_shell(self) -> None:
        with self.suspend():
            subprocess.run(["ssh", ssh.HOST])

    def action_btop(self) -> None:
        # -t forces a TTY: btop is a curses app, and a bare `ssh host btop`
        # gets no terminal to draw on. action_shell above needs no such flag
        # because an interactive login session allocates one on its own.
        with self.suspend():
            subprocess.run(["ssh", "-t", ssh.HOST, "btop"])


def main() -> None:
    HearthTuiApp().run()


if __name__ == "__main__":
    main()

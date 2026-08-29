"""hearth-tui: a terminal dashboard for the Hearth home server.

Wraps the SSH commands already run against Hearth (scripts/hearth-healthcheck.sh,
hearth-disk, scripts/hearth-deploy.sh, restic, journalctl) as Textual screens
instead of re-deriving their logic — see each screen module's docstring.
Run from Tawa/Theseus; talks to Hearth over the `hearth` SSH alias (hearth_tui.ssh).
"""

from __future__ import annotations

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, ListItem, ListView, Static

from hearth_tui.screens.deploy import DeployScreen
from hearth_tui.screens.disk import DiskScreen
from hearth_tui.screens.status import StatusScreen

# One entry per screen. Children add to this dict and to MainMenu's list —
# a one-line change each, per the pack's plan.
SCREENS: dict[str, type[Screen]] = {
    "status": StatusScreen,
    "disk": DiskScreen,
    "deploy": DeployScreen,
}

# (screen name, label) — display order for the main menu.
MENU_ITEMS: list[tuple[str, str]] = [
    ("status", "Status — health check + network"),
    ("disk", "Disk — COLD status / resume / park"),
    ("deploy", "Deploy — hearth-deploy.sh actions"),
]


class MainMenu(Screen):
    """Landing screen: pick a screen to open."""

    BINDINGS = [Binding("q", "app.quit", "Quit")]

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static("hearth-tui", id="title")
        yield ListView(
            *(ListItem(Static(label), name=name) for name, label in MENU_ITEMS),
            id="menu",
        )
        yield Footer()

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        name = event.item.name
        if name in SCREENS:
            self.app.push_screen(SCREENS[name]())


class HearthTuiApp(App):
    """Terminal dashboard for Hearth."""

    BINDINGS = [Binding("q", "quit", "Quit")]

    def on_mount(self) -> None:
        self.push_screen(MainMenu())


def main() -> None:
    HearthTuiApp().run()


if __name__ == "__main__":
    main()

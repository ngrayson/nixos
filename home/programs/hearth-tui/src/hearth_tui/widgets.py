"""Home-screen widgets: the navigation menu and the read-only stats panels.

Status and restic used to be their own screens; they're read-only "check and
glance away" data with no actions of their own, so each of their sections now
lives on the home screen as its own widget instead of needing a trip through
the menu. Every widget refreshes over its own `@work(thread=True)` worker, so
a slow SSH round trip never blocks the home screen's menu — disk/deploy/logs
stay as dedicated screens since they carry actions (park/switch/boot/tail)
that need their own key bindings and confirmation modals.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

from textual import work
from textual.message import Message
from textual.widgets import ListItem, ListView, Static

from hearth_tui import ssh
from hearth_tui.formatting import parse_ok_fail_lines

RESTIC_UNIT = "restic-backups-hearth.service"

WIDGET_BORDER_CSS = """
border: round $primary;
padding: 0 1;
height: auto;
"""

# Applied to widgets meant to sit two-up in a Horizontal pair (see app.py's
# MainMenu.compose) so each takes exactly half that row's width.
HALF_WIDTH_CSS = "width: 1fr;"

# Two /proc/stat samples 0.2s apart give an instantaneous CPU% (a single
# sample only has cumulative totals since boot); /proc/meminfo and the
# thermal-zone files under /sys need no extra packages on any Linux host.
SYSTEM_STATS_SCRIPT = """
read -r _ u1 n1 s1 i1 io1 irq1 si1 st1 _ < /proc/stat
sleep 0.2
read -r _ u2 n2 s2 i2 io2 irq2 si2 st2 _ < /proc/stat
idle1=$((i1+io1)); idle2=$((i2+io2))
total1=$((u1+n1+s1+i1+io1+irq1+si1+st1)); total2=$((u2+n2+s2+i2+io2+irq2+si2+st2))
totald=$((total2-total1)); idled=$((idle2-idle1))
if [ "$totald" -gt 0 ]; then
  echo "cpu_pct=$(( (100*(totald-idled)) / totald ))"
fi
awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{if(t)printf "mem_total_kb=%s\\nmem_avail_kb=%s\\n", t, a}' /proc/meminfo
for z in /sys/class/thermal/thermal_zone*; do
  [ -d "$z" ] || continue
  type=$(cat "$z/type" 2>/dev/null) || continue
  milli=$(cat "$z/temp" 2>/dev/null) || continue
  echo "temp:${type}=${milli}"
done
"""


def _parse_system_stats(
    text: str,
) -> tuple[int | None, int | None, int | None, list[tuple[str, float]]]:
    """Parse SYSTEM_STATS_SCRIPT's `key=value` lines into (cpu_pct, mem_total_kb,
    mem_avail_kb, [(zone_name, celsius), ...]).
    """
    cpu_pct = mem_total_kb = mem_avail_kb = None
    temps: list[tuple[str, float]] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("cpu_pct="):
            cpu_pct = int(stripped.split("=", 1)[1])
        elif stripped.startswith("mem_total_kb="):
            mem_total_kb = int(stripped.split("=", 1)[1])
        elif stripped.startswith("mem_avail_kb="):
            mem_avail_kb = int(stripped.split("=", 1)[1])
        elif stripped.startswith("temp:"):
            name, _, milli = stripped[len("temp:") :].partition("=")
            if milli.isdigit():
                temps.append((name, int(milli) / 1000))
    return cpu_pct, mem_total_kb, mem_avail_kb, temps


def _average_temps(temps: list[tuple[str, float]]) -> list[tuple[str, float]]:
    """Collapse per-zone readings into one averaged line per component.

    Hearth exposes a dozen thermal zones — several `acpitz`, an `iwlwifi_1`,
    per-core `coretemp` entries — which is more than a glance-and-look-away
    panel can carry. Zones of the same component differ only by a trailing
    index (`iwlwifi_1`, `coretemp2`), so stripping that groups them; a name
    with no index, like `x86_pkg_temp`, is its own component and passes
    through unchanged. First-seen order is preserved so the display doesn't
    reshuffle between refreshes.
    """
    # An underscore-separated index is unambiguous (`iwlwifi_1`), so it always
    # folds away.
    bases = [(re.sub(r"_\d+$", "", name), celsius) for name, celsius in temps]

    # A bare trailing digit is not: `SEN1`/`SEN2` are an indexed set, but
    # Hearth's `B0D4` is simply the ACPI device's name, and trimming it to
    # "B0D" would report a sensor that does not exist. Fold it only where it
    # actually groups two or more distinct zones.
    stems: dict[str, set[str]] = {}
    for name, _ in bases:
        stem = re.sub(r"\d+$", "", name)
        if stem:
            stems.setdefault(stem, set()).add(name)

    groups: dict[str, list[float]] = {}
    for name, celsius in bases:
        stem = re.sub(r"\d+$", "", name)
        component = stem if stem and len(stems.get(stem, ())) > 1 else name
        groups.setdefault(component, []).append(celsius)
    return [(name, sum(values) / len(values)) for name, values in groups.items()]


def _nixos_dir() -> Path:
    """Same NIXOS_DIR convention as scripts/hearth-deploy.sh (default ~/.config/nixos)."""
    return Path(os.environ.get("NIXOS_DIR", "~/.config/nixos")).expanduser()


def _parse_unit_config(cat_output: str) -> tuple[str | None, str | None, str | None]:
    """Extract (restic_bin, repository, password_file) from `systemctl cat` output.

    Discovered live from the running unit rather than hardcoded, since the
    nix store paths embedded in its ExecStart/Environment lines change across
    rebuilds.
    """
    repo = None
    password_file = None
    restic_bin = None
    for line in cat_output.splitlines():
        stripped = line.strip()
        match = re.match(r'Environment="RESTIC_REPOSITORY=(.*)"$', stripped)
        if match:
            repo = match.group(1)
            continue
        match = re.match(r'Environment="RESTIC_PASSWORD_FILE=(.*)"$', stripped)
        if match:
            password_file = match.group(1)
            continue
        match = re.match(r"ExecStart=(\S*/restic)\b", stripped)
        if match and restic_bin is None:
            restic_bin = match.group(1)
    return restic_bin, repo, password_file


class MenuList(ListView):
    """A `ListView` built from (name, label) pairs — the home screen's menu.

    Selection/navigation runs on the main thread's event loop, same as any
    Textual widget; every stats widget below refreshes on its own
    `@work(thread=True)` worker, so this stays responsive no matter what
    those workers are doing.
    """

    DEFAULT_CSS = f"""
    MenuList {{
        {WIDGET_BORDER_CSS}
    }}
    """

    def __init__(self, items: list[tuple[str, str]], *, id: str | None = None) -> None:
        super().__init__(
            *(ListItem(Static(label), name=name) for name, label in items),
            id=id,
        )


class HealthcheckWidget(Static):
    """scripts/hearth-healthcheck.sh's [ok]/[fail] probe results."""

    DEFAULT_CSS = f"""
    HealthcheckWidget {{
        {WIDGET_BORDER_CSS}
        {HALF_WIDTH_CSS}
    }}
    """

    def on_mount(self) -> None:
        self.refresh_data()

    def refresh_data(self) -> None:
        self.update("Refreshing…")
        self.run_healthcheck()

    @work(thread=True)
    def run_healthcheck(self) -> None:
        script = _nixos_dir() / "scripts" / "hearth-healthcheck.sh"
        if not script.is_file():
            self.app.call_from_thread(
                self.update,
                f"[red]Missing {script} — set NIXOS_DIR if the flake checkout lives elsewhere.[/red]",
            )
            return

        try:
            result = ssh.run_script(script, sudo=True, timeout=30)
        except ssh.SshError as exc:
            self.app.call_from_thread(self.update, f"[b]health[/b]\n[red]{exc}[/red]")
            return
        text = result.stdout + result.stderr
        rows = parse_ok_fail_lines(text)
        # COLD's mount belongs to the disk widget beside this one, which
        # reports it in the same words. Services — Jellyfin included — stay
        # here. Anchor on the mount check's own phrasing ("/mnt/cold is
        # mounted…", "…is not mounted") rather than the bare path: the
        # library rows point at /mnt/cold/<name> and are service state, not a
        # second mount report.
        shown = [row for row in rows if not row[1].startswith("/mnt/cold is")]
        if shown:
            lines = [
                f"[green]ok[/green]   {message}" if passed else f"[red]fail[/red] {message}"
                for passed, message in shown
            ]
        else:
            lines = [text.strip() or "(no output)"]
        self.app.call_from_thread(self.update, "[b]health[/b]\n" + "\n".join(lines))


class NetworkWidget(Static):
    """Raw `ip`/`ip route` output for Hearth's active link."""

    DEFAULT_CSS = f"""
    NetworkWidget {{
        {WIDGET_BORDER_CSS}
    }}
    """

    def on_mount(self) -> None:
        self.refresh_data()

    def refresh_data(self) -> None:
        self.update("Refreshing…")
        self.run_network()

    @work(thread=True)
    def run_network(self) -> None:
        try:
            result = ssh.run(
                "bash",
                "-c",
                "ip -br addr; echo ---; ip -br link; echo ---; ip route show default",
                timeout=15,
            )
        except ssh.SshError as exc:
            self.app.call_from_thread(self.update, f"[b]network[/b]\n[red]{exc}[/red]")
            return
        text = result.stdout or result.stderr or "(no output)"
        self.app.call_from_thread(self.update, f"[b]network[/b]\n{text}")


class DiskStatusWidget(Static):
    """COLD device/mount/Jellyfin status (hosts/Hearth/disk.nix's `hearth-disk status`)."""

    class StatusReady(Message):
        """Posted after each probe so the menu can name the action it would run.

        Carries the rows exactly as parsed, never a filtered view: the disk
        action is decided from the Jellyfin rows as well as the mount ones.
        """

        def __init__(self, rows: list[tuple[bool, str]]) -> None:
            super().__init__()
            self.rows = rows

    DEFAULT_CSS = f"""
    DiskStatusWidget {{
        {WIDGET_BORDER_CSS}
        {HALF_WIDTH_CSS}
    }}
    """

    def on_mount(self) -> None:
        self.refresh_data()

    def refresh_data(self) -> None:
        self.update("Refreshing…")
        self.run_status()

    @work(thread=True)
    def run_status(self) -> None:
        try:
            result = ssh.run("hearth-disk", "status", sudo=True, timeout=15)
        except ssh.SshError as exc:
            self.app.call_from_thread(self.update, f"[b]disk[/b]\n[red]{exc}[/red]")
            self.app.call_from_thread(self.post_message, self.StatusReady([]))
            return
        text = result.stdout + result.stderr
        rows = parse_ok_fail_lines(text)
        # Broadcast before filtering: the park/resume decision reads the
        # Jellyfin rows that the display below drops.
        self.app.call_from_thread(self.post_message, self.StatusReady(rows))

        # Jellyfin belongs to the health widget beside this one. Match
        # case-insensitively — `hearth-disk status` says "jellyfin is active"
        # but "Jellyfin health ...", and an undeployed Hearth may still be
        # emitting either spelling.
        shown = [row for row in rows if "jellyfin" not in row[1].lower()]
        if shown:
            lines = [
                f"[green]ok[/green]   {message}" if passed else f"[red]fail[/red] {message}"
                for passed, message in shown
            ]
        else:
            lines = [text.strip() or "(no output)"]
        self.app.call_from_thread(self.update, "[b]disk[/b]\n" + "\n".join(lines))


class SystemWidget(Static):
    """CPU/RAM use + thermal-zone temperatures, read straight from /proc and
    /sys — no extra packages needed on Hearth for any of these.
    """

    DEFAULT_CSS = f"""
    SystemWidget {{
        {WIDGET_BORDER_CSS}
        {HALF_WIDTH_CSS}
    }}
    """

    def on_mount(self) -> None:
        self.refresh_data()

    def refresh_data(self) -> None:
        self.update("Refreshing…")
        self.run_system_stats()

    @work(thread=True)
    def run_system_stats(self) -> None:
        try:
            result = ssh.run("bash", "-c", SYSTEM_STATS_SCRIPT, timeout=15)
        except ssh.SshError as exc:
            self.app.call_from_thread(self.update, f"[b]system[/b]\n[red]{exc}[/red]")
            return
        text = result.stdout or result.stderr or ""
        cpu_pct, mem_total_kb, mem_avail_kb, temps = _parse_system_stats(text)

        lines = []
        if cpu_pct is not None:
            lines.append(f"cpu    {cpu_pct}%")
        if mem_total_kb is not None and mem_avail_kb is not None:
            used_gb = (mem_total_kb - mem_avail_kb) / (1024 * 1024)
            total_gb = mem_total_kb / (1024 * 1024)
            pct = round((mem_total_kb - mem_avail_kb) / mem_total_kb * 100)
            lines.append(f"mem    {used_gb:.1f}G / {total_gb:.1f}G ({pct}%)")
        for name, celsius in _average_temps(temps):
            lines.append(f"{name}  {celsius:.1f}°C")
        if not lines:
            lines = [text.strip() or "(no output)"]
        self.app.call_from_thread(self.update, "[b]system[/b]\n" + "\n".join(lines))


class ResticRunWidget(Static):
    """Last-run state of restic-backups-hearth.service."""

    DEFAULT_CSS = f"""
    ResticRunWidget {{
        {WIDGET_BORDER_CSS}
        {HALF_WIDTH_CSS}
    }}
    """

    def on_mount(self) -> None:
        self.refresh_data()

    def refresh_data(self) -> None:
        self.update("Refreshing…")
        self.run_refresh()

    @work(thread=True)
    def run_refresh(self) -> None:
        try:
            result = ssh.run(
                "systemctl",
                "show",
                RESTIC_UNIT,
                "-p",
                "ActiveState,Result,ExecMainStartTimestamp,ExecMainExitTimestamp",
                timeout=15,
            )
        except ssh.SshError as exc:
            self.app.call_from_thread(
                self.update, f"[b]restic — last run[/b]\n[red]{exc}[/red]"
            )
            return
        text = (result.stdout or result.stderr or "(no output)").strip()
        self.app.call_from_thread(self.update, f"[b]restic — last run[/b]\n{text}")


class ResticSnapshotsWidget(Static):
    """Read-only restic snapshot list. Restoring is a deliberate manual
    runbook (hosts/Hearth/restic.md) — this widget never offers restore/
    prune/forget actions.
    """

    DEFAULT_CSS = f"""
    ResticSnapshotsWidget {{
        {WIDGET_BORDER_CSS}
        {HALF_WIDTH_CSS}
    }}
    """

    def on_mount(self) -> None:
        self.refresh_data()

    def refresh_data(self) -> None:
        self.update("Refreshing…")
        self.run_refresh()

    @work(thread=True)
    def run_refresh(self) -> None:
        try:
            cat_result = ssh.run("systemctl", "cat", RESTIC_UNIT, sudo=True, timeout=15)
        except ssh.SshError as exc:
            self.app.call_from_thread(
                self.update, f"[b]restic — snapshots[/b]\n[red]{exc}[/red]"
            )
            return
        restic_bin, repo, password_file = _parse_unit_config(cat_result.stdout)
        if not (restic_bin and repo and password_file):
            self.app.call_from_thread(
                self.update,
                "[red]Could not discover the restic binary/repository/password-file "
                f"from {RESTIC_UNIT} — check `ssh hearth sudo systemctl cat {RESTIC_UNIT}`.[/red]",
            )
            return

        try:
            snap_result = ssh.run(
                restic_bin,
                "-r",
                repo,
                "--password-file",
                password_file,
                "snapshots",
                "--json",
                sudo=True,
                timeout=30,
            )
        except ssh.SshError as exc:
            self.app.call_from_thread(
                self.update, f"[b]restic — snapshots[/b]\n[red]{exc}[/red]"
            )
            return
        self._render_snapshots(snap_result.stdout, snap_result.stderr)

    def _render_snapshots(self, stdout: str, stderr: str) -> None:
        try:
            parsed = json.loads(stdout) if stdout.strip() else []
        except json.JSONDecodeError:
            text = f"[red]{(stdout + stderr).strip() or '(no output)'}[/red]"
            self.app.call_from_thread(self.update, text)
            return

        if isinstance(parsed, dict) and parsed.get("message_type") == "exit_error":
            # e.g. the repo path under /mnt/cold is unreachable — COLD is parked.
            text = f"[yellow]{parsed.get('message', 'repository unavailable — is COLD mounted?')}[/yellow]"
        elif isinstance(parsed, list):
            if not parsed:
                text = "(no snapshots yet)"
            else:
                lines = [
                    f"{snap.get('short_id', '?')}  {snap.get('time', '?')[:19]}  "
                    + ",".join(snap.get("tags", []) or [])
                    for snap in parsed
                ]
                text = "\n".join(lines)
        else:
            text = f"[red]Unexpected restic output: {stdout.strip()}[/red]"
        self.app.call_from_thread(self.update, f"[b]restic — snapshots[/b]\n{text}")

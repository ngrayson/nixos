"""decide_disk_action over `hearth-disk status` output as the widget sees it.

hearth-disk prints [ok] rows to stdout and [fail] rows to stderr; the widget
joins stdout + stderr, so every case below lists the ok rows first.
"""

from hearth_tui.disk_action import decide_disk_action
from hearth_tui.formatting import parse_ok_fail_lines


def joined(oks: list[str], fails: list[str]) -> list[tuple[bool, str]]:
    stdout = "".join(f"[ok]   {m}\n" for m in oks)
    stderr = "".join(f"[fail] {m}\n" for m in fails)
    return parse_ok_fail_lines(stdout + stderr)


DEVICE = "device /dev/disk/by-uuid/X present"
MOUNTED = "/mnt/cold is mounted (UUID X)"
NOT_MOUNTED = "/mnt/cold is not mounted with UUID X"
JF_UP = "Jellyfin is active"
JF_DOWN = "Jellyfin is not active (inactive)"
ST_UP = "Syncthing is active"
ST_DOWN = "Syncthing is not active (inactive)"
NOT_MASKED = "mnt-cold.mount is not masked"


def test_serving_offers_park():
    rows = joined([DEVICE, MOUNTED, JF_UP, ST_UP, "Jellyfin health http://x/health", NOT_MASKED], [])
    assert decide_disk_action(rows) == "park"


def test_plugged_in_not_mounted_offers_resume():
    # The audit case: the old positional read took the "not masked" ok row as
    # "mounted" and answered "unclear".
    rows = joined([DEVICE, NOT_MASKED], [NOT_MOUNTED, JF_DOWN, ST_DOWN, "Jellyfin health URL failed (x)"])
    assert decide_disk_action(rows) == "resume"


def test_mounted_but_jellyfin_crashed_is_unclear_not_park():
    # The audit case: the old positional read took the Syncthing row as
    # Jellyfin and offered Park.
    rows = joined([DEVICE, MOUNTED, ST_UP, NOT_MASKED], [JF_DOWN, "Jellyfin health URL failed (x)"])
    assert decide_disk_action(rows) == "unclear"


def test_unplugged_is_unclear():
    rows = joined([NOT_MASKED], ["COLD device missing (X) — enclosure unplugged", NOT_MOUNTED, JF_DOWN])
    assert decide_disk_action(rows) == "unclear"


def test_no_output_is_unclear():
    assert decide_disk_action([]) == "unclear"

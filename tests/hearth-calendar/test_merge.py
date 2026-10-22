"""The ICS merger keeps folded lines intact and tags events by feed.

python3 tests/hearth-calendar/test_merge.py <path to intranet-calendar-merge.py>
(flake check: hearth-calendar-tests). Imports body_lines only; nothing is fetched.
"""

import importlib.util
import sys

spec = importlib.util.spec_from_file_location("merge", sys.argv[1])
merge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge)

FEED = "\r\n".join([
    "BEGIN:VCALENDAR", "VERSION:2.0",
    "BEGIN:VEVENT", "UID:a", "SUMMARY:Dinner with ", " Bob", "END:VEVENT",
    "END:VCALENDAR", "",
])


def unfold(lines):
    return "\n".join(lines).replace("\n ", "")


failures = 0


def check(desc, ok):
    global failures
    print(("  [PASS] " if ok else "  [FAIL] ") + desc)
    failures += 0 if ok else 1


lines = merge.body_lines(FEED, "Family", "abc@group.calendar.google.com")
check("folded SUMMARY keeps its space", "SUMMARY:Dinner with Bob" in unfold(lines).split("\n"))
check("VCALENDAR wrapper dropped", not any(l.startswith(("BEGIN:VCALENDAR", "END:VCALENDAR")) for l in lines))
check("event tagged with feed name", "X-HEARTH-CALENDAR:Family" in lines)
check("feed name is ICS-escaped", merge.escape("a,b;c") == r"a\,b\;c")
sys.exit(1 if failures else 0)

"""snapshot_text: restic's exit code decides before its (possibly empty) stdout."""

import json

from hearth_tui.formatting import snapshot_text

EXIT_ERROR = json.dumps({"message_type": "exit_error", "code": 1,
                         "message": "Fatal: unable to open repository at /mnt/cold/backups/hearth-restic"})


def test_parked_cold_is_an_error_not_an_empty_repo():
    # restic --json: error object on stderr, nothing on stdout, exit 1.
    text = snapshot_text(1, "", EXIT_ERROR + "\n")
    assert "no snapshots" not in text
    assert "unable to open repository" in text


def test_plain_failure_shows_last_stderr_line():
    text = snapshot_text(1, "", "some warning\nFatal: wrong password or no key found\n")
    assert "no snapshots" not in text
    assert "wrong password" in text and "exit 1" in text


def test_failure_without_output_still_says_failed():
    assert "failed" in snapshot_text(255, "", "")


def test_empty_repo_succeeds():
    assert snapshot_text(0, "[]", "") == "(no snapshots yet)"


def test_snapshots_listed():
    snaps = [{"short_id": "ab12cd34", "time": "2026-10-22T03:00:01.123Z", "tags": ["nightly"]}]
    assert snapshot_text(0, json.dumps(snaps), "") == "ab12cd34  2026-10-22T03:00:01  nightly"


def test_markup_in_messages_is_escaped():
    text = snapshot_text(1, "", "Fatal: [bold]oops\n")
    assert "\\[bold]" in text

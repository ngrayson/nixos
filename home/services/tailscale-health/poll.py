"""Poll tailscaled's health and write a small JSON file the Quickshell bar reads.

Run by the qs-tailscale-health user timer every 10 s (see ../tailscale-health.nix
for the wrapper that resolves the defaults below). Stdlib only.

Environment:
  QS_TS_OUT          state file to write (the wrapper defaults it to
                     $XDG_RUNTIME_DIR/tailscale-health/state.json)
  QS_TS_STATUS_FILE  test hook: read this JSON instead of running the CLI
  QS_TS_NOTIFY       notifier command, default notify-send; tests set `true`

Debounce is the load-bearing rule. `warming-up` and `no-derp-connection`
flap for a few seconds on every resume, so a warning only becomes ACTIVE
once it has been present for two consecutive polls at least 15 s apart.
Only active warnings reach the pill and the notification.

Personal data: only BackendState and the Health message strings are ever
written. Never persist Self, Peer, CurrentTailnet, MagicDNSSuffix or
TailscaleIPs -- the tailnet name and addresses are personal, and the state
file is readable to anything running as this user.
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time

ACTIVE_AFTER_SEC = 15
STACK_TAG = "string:x-dunst-stack-tag:qs-tailscale-health"


def read_status():
    """Return (backend, health) from the CLI or the test fixture.

    Any failure -- CLI missing, timeout, non-zero exit, unparsable JSON --
    reads as an unreachable daemon with no warnings. That is a pill state,
    not an error worth a stack trace.
    """
    fixture = os.environ.get("QS_TS_STATUS_FILE")
    try:
        if fixture:
            body = json.loads(pathlib.Path(fixture).read_text(encoding="utf-8"))
        else:
            proc = subprocess.run(
                ["tailscale", "status", "--json"],
                capture_output=True, text=True, timeout=5, check=False)
            if proc.returncode != 0:
                return "unreachable", []
            body = json.loads(proc.stdout)
    except Exception:
        return "unreachable", []

    backend = body.get("BackendState") or "unreachable"
    health = body.get("Health") or []
    # Keep only strings; the LocalAPI exposes message text, nothing else.
    return str(backend), [str(h) for h in health if h]


def read_previous(out):
    try:
        prev = json.loads(out.read_text(encoding="utf-8"))
        if not isinstance(prev, dict):
            return {}
        return prev
    except Exception:
        return {}


def write_atomic(out, payload):
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = tempfile.NamedTemporaryFile(
        "w", dir=str(out.parent), delete=False, encoding="utf-8")
    json.dump(payload, tmp)
    tmp.flush()
    os.fsync(tmp.fileno())
    tmp.close()
    os.replace(tmp.name, str(out))


def notify(args):
    """Fire the notifier; never let a failure here fail the unit."""
    cmd = os.environ.get("QS_TS_NOTIFY") or "notify-send"
    try:
        subprocess.run([cmd, *args], check=False, timeout=10,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def main():
    out = pathlib.Path(os.environ.get("QS_TS_OUT") or "state.json")
    now = int(time.time())

    backend, health = read_status()
    prev = read_previous(out)
    prev_first = {
        w.get("text"): w.get("firstSeen")
        for w in (prev.get("warnings") or [])
        if isinstance(w, dict) and w.get("text")
    }
    was_notified = bool(prev.get("notified", False))

    warnings = []
    for text in health:
        first = prev_first.get(text)
        if not isinstance(first, int):
            first = now
        warnings.append({
            "text": text,
            "firstSeen": first,
            "active": (now - first) >= ACTIVE_AFTER_SEC,
        })

    active = [w["text"] for w in warnings if w["active"]]

    # One critical notification per episode, replaced by a short all-clear.
    # A non-Running backend is shown by the pill but never notifies: a
    # stopped daemon on a desktop is not an emergency.
    notified = was_notified
    if active and not was_notified:
        notify(["--urgency=critical", "--app-name=tailscale", "-h", STACK_TAG,
                "Tailscale: " + active[0], "\n".join(active)])
        notified = True
    elif not active and was_notified:
        notify(["--app-name=tailscale", "-h", STACK_TAG,
                "Tailscale healthy again"])
        notified = False

    write_atomic(out, {
        "ok": True,
        "generatedAt": now,
        "backend": backend,
        "warnings": warnings,
        "notified": notified,
    })


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Always exit 0; a broken poll must not fail the timer unit.
        pass
    sys.exit(0)

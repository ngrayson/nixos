# Polls a Google Calendar "secret iCal address" (a read-only .ics URL) on a
# timer and writes a flat JSON file the Quickshell calendar popup reads. This
# mirrors the repo's established "small script polls an external source on a
# timer, writes simplified JSON, the UI just reads it" shape (see the Hearth
# dashboard's weather/AQI pollers) -- but locally, as a systemd --user unit.
#
# Why a script instead of parsing ICS in QML: recurring events (RRULE) are a
# real parsing problem. This uses icalendar + recurring-ical-events to expand
# them, so the QML never sees an RRULE -- only concrete dated occurrences.
#
# The ICS URL is a secret (it grants read access to the calendar). It is read
# at RUNTIME from the sops secret path; nothing here logs or embeds it, and the
# whole thing degrades to an empty events list when the secret is absent, so
# the calendar grid still works before Nick provisions it. See
# common/sops.nix (secret `desktop-calendar-ics`).
{
  lib,
  pkgs,
  ...
}: let
  # How far around today to expand occurrences. The popup shows the current
  # month plus an upcoming-events list, so a window that comfortably covers a
  # month view in either direction is plenty.
  windowPastDays = 40;
  windowFutureDays = 120;
  intervalSec = 1800; # 30 min -- calendar events don't need fresher.

  pyEnv = pkgs.python3.withPackages (ps: with ps; [icalendar recurring-ical-events]);

  calendarSync = pkgs.writeShellApplication {
    name = "quickshell-calendar-sync";
    runtimeInputs = [pkgs.coreutils pyEnv];
    text = ''
      set -euo pipefail

      # Test hook: the unit sets neither; they let the whole fetch be exercised
      # against a scratch file and output path without the real secret.
      # Resolve the defaults, then hand the resolved values to Python via the
      # names it reads. Exporting the raw QS_CAL_ICS_FILE would skip the default.
      QS_CAL_ICS_FILE="''${QS_CAL_ICS_FILE:-/run/secrets/desktop-calendar-ics}"
      OUT="''${QS_CAL_OUT:-''${XDG_CACHE_HOME:-$HOME/.cache}/quickshell-calendar.json}"

      mkdir -p "$(dirname "$OUT")"

      export QS_CAL_ICS_FILE OUT
      export QS_CAL_PAST_DAYS=${toString windowPastDays}
      export QS_CAL_FUTURE_DAYS=${toString windowFutureDays}

      python3 - <<'PY'
      import json, os, sys, tempfile, pathlib, urllib.request
      from datetime import datetime, date, timedelta, timezone

      out = pathlib.Path(os.environ["OUT"])
      ics_file = os.environ.get("QS_CAL_ICS_FILE", "")
      past_days = int(os.environ.get("QS_CAL_PAST_DAYS", "40"))
      future_days = int(os.environ.get("QS_CAL_FUTURE_DAYS", "120"))

      def write(payload):
          tmp = tempfile.NamedTemporaryFile(
              "w", dir=str(out.parent), delete=False, encoding="utf-8")
          json.dump(payload, tmp)
          tmp.flush()
          os.fsync(tmp.fileno())
          tmp.close()
          os.replace(tmp.name, str(out))

      now = int(datetime.now(timezone.utc).timestamp())

      # No secret yet: write an empty-but-valid file so the popup shows the
      # grid with an empty events list rather than looking broken.
      url = ""
      if ics_file:
          try:
              url = pathlib.Path(ics_file).read_text(encoding="utf-8").strip()
          except OSError:
              url = ""
      if not url:
          write({"ok": False, "reason": "no-ics-url", "generatedAt": now, "events": []})
          sys.exit(0)

      try:
          req = urllib.request.Request(url, headers={"User-Agent": "quickshell-calendar"})
          with urllib.request.urlopen(req, timeout=30) as resp:
              raw = resp.read()
      except Exception as exc:  # noqa: BLE001 -- any fetch failure is non-fatal
          write({"ok": False, "reason": "fetch-failed:" + type(exc).__name__,
                 "generatedAt": now, "events": []})
          sys.exit(0)

      try:
          import icalendar
          import recurring_ical_events

          cal = icalendar.Calendar.from_ical(raw)
          start = date.today() - timedelta(days=past_days)
          end = date.today() + timedelta(days=future_days)
          occurrences = recurring_ical_events.of(cal).between(start, end)

          def convert(v):
              # Returns (epoch_seconds, is_all_day, "YYYY-MM-DD"). The day string
              # is the calendar day the UI buckets by, computed here so QML never
              # has to juggle timezones: all-day events keep their plain date
              # (no tz shift), timed events use the viewer-local day (this runs
              # on the same host as the bar).
              if isinstance(v, datetime):
                  if v.tzinfo is None:
                      v = v.replace(tzinfo=timezone.utc)
                  epoch = int(v.timestamp())
                  day = datetime.fromtimestamp(epoch).strftime("%Y-%m-%d")
                  return epoch, False, day
              if isinstance(v, date):
                  dt = datetime(v.year, v.month, v.day, tzinfo=timezone.utc)
                  return int(dt.timestamp()), True, v.strftime("%Y-%m-%d")
              return None, False, ""

          events = []
          for comp in occurrences:
              dtstart = comp.get("DTSTART")
              if dtstart is None:
                  continue
              s_epoch, all_day, day = convert(dtstart.dt)
              if s_epoch is None:
                  continue
              dtend = comp.get("DTEND")
              e_epoch = s_epoch
              if dtend is not None:
                  ee, _, _ = convert(dtend.dt)
                  if ee is not None:
                      e_epoch = ee
              title = str(comp.get("SUMMARY", "") or "").strip() or "(untitled)"
              events.append({"title": title, "start": s_epoch, "end": e_epoch,
                             "allDay": all_day, "day": day})

          events.sort(key=lambda e: e["start"])
          write({"ok": True, "generatedAt": now, "events": events})
      except Exception as exc:  # noqa: BLE001 -- parse failure must not crash the timer
          write({"ok": False, "reason": "parse-failed:" + type(exc).__name__,
                 "generatedAt": now, "events": []})
          sys.exit(0)
      PY
    '';
  };
in {
  home.packages = [calendarSync];

  systemd.user.services.quickshell-calendar-sync = {
    Unit = {
      Description = "Fetch and expand Google Calendar (.ics) events for the Quickshell popup";
      # Needs the network up to fetch; a failure still writes an empty file.
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe calendarSync;
    };
  };

  systemd.user.timers.quickshell-calendar-sync = {
    Unit.Description = "Refresh Quickshell calendar events";
    Timer = {
      OnStartupSec = "20s";
      OnUnitActiveSec = "${toString intervalSec}s";
      AccuracySec = "1m";
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}

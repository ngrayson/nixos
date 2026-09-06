# Polls Claude's OAuth usage endpoint on a timer and writes a flat JSON file
# the Quickshell bar's Claude pill reads. Same shape as
# ./calendar-sync.nix: a small script owns the network call and the parsing,
# the UI only ever reads simplified JSON.
#
# AUTH, AND THE ONE RULE THAT MATTERS: the access token comes from Claude
# Code's own credentials file (~/.claude/.credentials.json, mode 0600, owner
# wiz -- the bar runs as wiz, so it can read it). That token lives about eight
# hours and ONLY Claude Code refreshes it, using a refresh token with a much
# longer life. This poller is a strictly READ-ONLY consumer of that file: two
# writers would corrupt Claude Code's sign-in. When the token has expired the
# poller reports `auth-expired` and the pill says to run `claude`, which is the
# correct fix and costs the user nothing.
#
# Nothing here logs, copies or writes the access token, the refresh token, or
# the organizationUuid that sits beside them; failures record only the
# exception's class name.
{
  lib,
  pkgs,
  ...
}: let
  # One poll per five minutes is far below any rate limit and keeps the reset
  # countdowns honest to the minute. The menu also refreshes on open.
  intervalSec = 300;

  claudeUsage = pkgs.writeShellApplication {
    name = "qs-claude-usage";
    runtimeInputs = [pkgs.coreutils pkgs.python3];
    text = ''
      set -euo pipefail

      # Test hooks: the unit sets neither. They let the whole fetch be
      # exercised against a scratch credentials file and output path. Resolve
      # the defaults here and hand the resolved values to Python under the
      # names it reads -- exporting the raw QS_CLAUDE_CREDS would skip the
      # default when it is unset.
      CREDS="''${QS_CLAUDE_CREDS:-$HOME/.claude/.credentials.json}"
      OUT="''${QS_CLAUDE_OUT:-''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/claude-usage/state.json}"

      mkdir -p "$(dirname "$OUT")"

      export CREDS OUT

      python3 - <<'PY'
      import json, os, pathlib, tempfile, time, urllib.error, urllib.request

      out = pathlib.Path(os.environ["OUT"])
      creds_path = pathlib.Path(os.environ["CREDS"])

      URL = "https://api.anthropic.com/api/oauth/usage"
      BETA = "oauth-2025-04-20"


      def write(payload):
          payload["generatedAt"] = int(time.time())
          tmp = tempfile.NamedTemporaryFile(
              "w", dir=str(out.parent), delete=False, encoding="utf-8")
          json.dump(payload, tmp)
          tmp.flush()
          os.fsync(tmp.fileno())
          tmp.close()
          os.replace(tmp.name, str(out))


      def fail(reason):
          write({"ok": False, "reason": reason, "plan": None,
                 "limits": [], "extraUsage": {"enabled": False, "utilization": 0}})


      def epoch(value):
          # resets_at is ISO 8601 with a Z suffix; QML wants a plain epoch.
          if not value:
              return None
          try:
              from datetime import datetime
              return int(datetime.fromisoformat(
                  str(value).replace("Z", "+00:00")).timestamp())
          except Exception:
              return None


      def simplify(entry):
          scope = entry.get("scope") or {}
          model = scope.get("model") or {}
          return {
              "kind": entry.get("kind"),
              "group": entry.get("group"),
              "percent": entry.get("percent"),
              "severity": entry.get("severity"),
              "resetsAt": epoch(entry.get("resets_at")),
              "scope": model.get("display_name"),
              "isActive": bool(entry.get("is_active", True)),
          }


      try:
          creds = json.loads(creds_path.read_text(encoding="utf-8"))
      except Exception:
          # Absent or unreadable is a normal state on a machine where Claude
          # Code has never signed in -- not an error worth a stack trace.
          fail("no-credentials")
          raise SystemExit(0)

      token = (creds.get("claudeAiOauth") or {}).get("accessToken")
      if not token:
          fail("no-credentials")
          raise SystemExit(0)

      req = urllib.request.Request(URL, headers={
          "Authorization": "Bearer " + token,
          "anthropic-beta": BETA,
          "User-Agent": "qs-claude-usage",
      })

      try:
          with urllib.request.urlopen(req, timeout=15) as resp:
              body = json.loads(resp.read().decode("utf-8"))
      except urllib.error.HTTPError as exc:
          # 401/403 means the ~8h access token aged out. Only Claude Code can
          # refresh it, so say so rather than retrying into the same wall.
          fail("auth-expired" if exc.code in (401, 403) else "fetch-failed:HTTPError")
          raise SystemExit(0)
      except Exception as exc:
          fail("fetch-failed:" + type(exc).__name__)
          raise SystemExit(0)

      extra = body.get("extra_usage") or {}
      write({
          "ok": True,
          "reason": None,
          "plan": (creds.get("claudeAiOauth") or {}).get("subscriptionType"),
          "limits": [simplify(e) for e in (body.get("limits") or [])],
          "extraUsage": {
              "enabled": bool(extra.get("is_enabled", False)),
              "utilization": extra.get("utilization", 0),
          },
      })
      PY
    '';
  };
in {
  home.packages = [claudeUsage];

  systemd.user.services.qs-claude-usage = {
    Unit = {
      Description = "Fetch Claude usage limits for the Quickshell bar pill";
      # Needs the network; a failure still writes a file saying why.
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe claudeUsage;
    };
  };

  systemd.user.timers.qs-claude-usage = {
    Unit.Description = "Refresh Claude usage for the Quickshell bar";
    Timer = {
      OnStartupSec = "30s";
      OnUnitActiveSec = "${toString intervalSec}s";
      AccuracySec = "30s";
    };
    Install.WantedBy = ["timers.target"];
  };
}

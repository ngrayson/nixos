# Conveyor Personal Compute VM (conveyor-k3) for the Quickshell bar pill.
# Same shape as ./claude-usage.nix: a user timer runs a poller that owns every
# call to the CLI and writes one flat JSON file; the bar only reads it. Actions
# go through qs-conveyor-vm-ctl, the single writer (like hypr-sunset-ctl), so
# the bar never runs conveyor-k3 or limactl itself.
#
# THE CLI IS THE CONTRACT: `vm list --json`, `vm status --json` and `vm pods`.
# Never limactl, never the instance's state dir -- conveyor-k3 owns those and
# serialises its own operations behind operation.lock. Stops are graceful by
# default (`vm stop`, which refuses while a card runs); `--force` is only ever
# the menu's "Force stop".
#
# PERSONAL DATA: `vm list/status --json` carry linkedAccount (the account's
# email and display name). The poller drops it and approvedDestinations before
# writing, so neither reaches the state file, the bar or a log.
#
# Hosts with no instance (Theseus) never run the poller: the unit is
# conditioned on the instances directory, and an absent state file hides the
# pill. Test hooks: CONVEYOR_K3 (the CLI to call) and QS_CVM_OUT (state file).
{
  lib,
  pkgs,
  ...
}: let
  intervalSec = 10;

  # `vm pods` shells into the guest; poll it at most every this many seconds.
  podsEverySec = 30;

  runtime = [
    pkgs.coreutils
    pkgs.jq
    pkgs.libnotify
    pkgs.util-linux # setsid
    pkgs.kitty
    pkgs.xdg-utils
    pkgs.python3
    pkgs.nodejs # conveyor-k3 is `#!/usr/bin/env node`
    pkgs.procps # kill
  ];

  # Resolve the CLI and the state dir identically in both scripts. The CLI is
  # npm-installed (home/programs/conveyor-k3.nix); a systemd user unit and the
  # bar's Process env do not see the login shell's ~/.npm-global/bin.
  prelude = ''
    CK3="''${CONVEYOR_K3:-$HOME/.npm-global/bin/conveyor-k3}"
    OUT="''${QS_CVM_OUT:-''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/conveyor-vm/state.json}"
    DIR="$(dirname "$OUT")"
    mkdir -p "$DIR"
  '';

  status = pkgs.writeShellApplication {
    name = "qs-conveyor-vm-status";
    runtimeInputs = runtime;
    text = ''
      ${prelude}
      export CK3 OUT DIR
      python3 - <<'PY'
      import glob, json, os, pathlib, subprocess, tempfile, time

      CK3, OUT, DIR = os.environ["CK3"], pathlib.Path(os.environ["OUT"]), os.environ["DIR"]
      PODS_EVERY = ${toString podsEverySec}
      now = int(time.time())


      def write(payload):
          payload["generatedAt"] = now
          tmp = tempfile.NamedTemporaryFile("w", dir=DIR, delete=False, encoding="utf-8")
          json.dump(payload, tmp)
          tmp.flush()
          os.fsync(tmp.fileno())
          tmp.close()
          os.replace(tmp.name, str(OUT))


      def cli(*args, timeout=20):
          r = subprocess.run([CK3, *args], capture_output=True, text=True, timeout=timeout)
          if r.returncode != 0:
              raise RuntimeError("exit %d" % r.returncode)
          text = r.stdout
          return json.loads(text[text.find("{"):])


      def alive(pid):
          try:
              os.kill(int(pid), 0)
              return True
          except Exception:
              return False


      try:
          prev = {i["instance"]: i for i in json.loads(OUT.read_text()).get("instances", [])}
      except Exception:
          prev = {}

      if not os.access(CK3, os.X_OK):
          write({"ok": False, "reason": "no-cli", "host": None, "instances": []})
          raise SystemExit(0)

      try:
          listing = cli("vm", "list", "--json")
      except Exception as e:
          write({"ok": False, "reason": "list-failed: " + type(e).__name__, "host": None, "instances": []})
          raise SystemExit(0)

      instances = []
      for inst in listing.get("instances", []):
          name = inst.get("instance")
          row = {
              "instance": name,
              "status": inst.get("status"),
              "enrolled": inst.get("enrolled") is True,
              "linkVerified": inst.get("linkVerified") is True,
              "operationInProgress": inst.get("operationInProgress") is True,
              "resources": inst.get("resources") or {},
              "guard": None,
              "errorsCount": 0,
              "lastStop": None,
              "pods": None,
              "pending": None,
          }
          try:
              st = cli("vm", "status", "--json", "--instance=" + name)
              g = st.get("guard") or {}
              obs = g.get("observed") or {}
              row["guard"] = {
                  "status": g.get("status"),
                  "startedAt": g.get("startedAt"),
                  "rssKiB": obs.get("rssKiB"),
                  "diskBytes": obs.get("diskBytes"),
                  "freeBytes": obs.get("freeBytes"),
              }
              row["errorsCount"] = len(st.get("errors") or [])
              ls = st.get("lastStop") or None
              row["lastStop"] = {k: ls.get(k) for k in ("status", "reason", "at")} if ls else None
          except Exception:
              pass

          # Pods: only on a running, enrolled guest, at most every PODS_EVERY s.
          # Any failure is "unknown" (null), which the bar and ctl treat as busy.
          old = (prev.get(name) or {}).get("pods")
          if row["status"] == "Running" and row["enrolled"]:
              if old and now - int(old.get("checkedAt") or 0) < PODS_EVERY:
                  row["pods"] = old
              else:
                  try:
                      p = cli("vm", "pods", "--instance=" + name, timeout=25)
                      running = sum(1 for x in p.get("pods", []) if x.get("phase") in ("Running", "Pending"))
                      row["pods"] = {"running": running, "checkedAt": now}
                  except Exception:
                      row["pods"] = None

          # A transition qs-conveyor-vm-ctl started. Its runner removes the
          # file itself on exit; a file whose pid is gone is stale (killed
          # runner, reboot) and is dropped here.
          pf = os.path.join(DIR, "pending-%s.json" % name)
          try:
              pend = json.loads(pathlib.Path(pf).read_text())
              if alive(pend.get("pid", 0)):
                  row["pending"] = {"transition": pend.get("transition"), "since": pend.get("since")}
              else:
                  os.remove(pf)
          except FileNotFoundError:
              pass
          except Exception:
              pass

          instances.append(row)

      host = listing.get("host") or {}
      write({
          "ok": True,
          "reason": None,
          "host": {k: host.get(k) for k in ("cpus", "memoryGiB", "memoryBudgetGiB", "allocatedHostMemoryGiB")},
          "instances": instances,
      })
      PY
    '';
  };

  ctl = pkgs.writeShellApplication {
    name = "qs-conveyor-vm-ctl";
    runtimeInputs = runtime;
    text = ''
      ${prelude}
      PANEL_URL="https://conveyor.rallycryapp.com/profile/integrations"
      # Re-invoke this exact script by store path: a detached runner does not
      # inherit the bar's PATH, so the bare name may not resolve.
      self="$0"

      usage() {
        echo "usage: qs-conveyor-vm-ctl <start|stop|stop-when-idle|cancel-stop|force-stop|open-panel|logs|refresh> --instance=<name>" >&2
        exit 2
      }

      action="''${1:-}"
      [ -n "$action" ] || usage
      shift
      inst=""
      for a in "$@"; do
        case "$a" in
          --instance=*) inst="''${a#--instance=}" ;;
        esac
      done
      case "$action" in
        open-panel|refresh|_*) ;;
        *) [ -n "$inst" ] || usage ;;
      esac

      pending="$DIR/pending-$inst.json"

      note() { notify-send --app-name=conveyor-vm "$@" || true; }
      refresh() { systemctl --user start --no-block qs-conveyor-vm-status.service 2>/dev/null || qs-conveyor-vm-status || true; }

      # Running-card count from the poller's last write: a number, or
      # "unknown" when the poller could not ask the guest (unknown is busy).
      cards() {
        jq -r --arg i "$inst" \
          '(.instances[]? | select(.instance == $i) | .pods.running) // "unknown"' \
          "$OUT" 2>/dev/null || echo unknown
      }

      live_pending() {
        [ -f "$pending" ] || return 1
        pid="$(jq -r '.pid // 0' "$pending" 2>/dev/null || echo 0)"
        [ "$pid" -gt 0 ] 2>/dev/null && kill -0 "$pid" 2>/dev/null
      }

      # Background runner: records itself in the pending file (so the pill
      # reacts at once and the poller can tell a live operation from a stale
      # file), runs one CLI operation, notifies on failure, cleans up.
      spawn() { # spawn <transition> <cli args...>
        setsid -f "$self" _run "$@" --instance="$inst" >/dev/null 2>&1 < /dev/null
      }

      case "$action" in
        start)
          live_pending && { note "Conveyor VM $inst is busy" "Another start or stop is still running."; exit 0; }
          spawn starting vm start
          ;;
        stop)
          live_pending && { note "Conveyor VM $inst is busy" "Another start or stop is still running."; exit 0; }
          n="$(cards)"
          if [ "$n" = 0 ]; then
            spawn stopping vm stop
          else
            exec "$self" stop-when-idle --instance="$inst"
          fi
          ;;
        stop-when-idle)
          live_pending && { note "Conveyor VM $inst is busy" "A start, stop or drain is already running."; exit 0; }
          setsid -f "$self" _drain --instance="$inst" >/dev/null 2>&1 < /dev/null
          note "Conveyor VM $inst will stop after the running card" "Turn off Accept new work in the Personal Compute panel so no new card lands meanwhile."
          ;;
        cancel-stop)
          if live_pending && [ "$(jq -r .transition "$pending")" = draining ]; then
            kill "$(jq -r .pid "$pending")" 2>/dev/null || true
            note "Conveyor VM $inst" "Pending stop cancelled."
          fi
          ;;
        force-stop)
          if live_pending && [ "$(jq -r .transition "$pending")" = draining ]; then
            kill "$(jq -r .pid "$pending")" 2>/dev/null || true
          fi
          spawn stopping vm stop --force
          ;;
        open-panel)
          xdg-open "$PANEL_URL" >/dev/null 2>&1 &
          ;;
        logs)
          if "$CK3" vm service status --json --instance="$inst" 2>/dev/null | jq -e '.installed == true' >/dev/null; then
            setsid -f kitty --title conveyor-vm journalctl --user -u "conveyor-k3-vm@$inst" -f >/dev/null 2>&1
          else
            setsid -f kitty --hold --title conveyor-vm "$CK3" vm status --instance="$inst" >/dev/null 2>&1
          fi
          ;;
        refresh)
          refresh
          ;;

        _run) # _run <transition> <cli args...> --instance=<i>
          transition="$1"
          shift
          args=()
          for a in "$@"; do
            case "$a" in --instance=*) ;; *) args+=("$a") ;; esac
          done
          printf '{"transition":"%s","since":%s,"pid":%s}\n' "$transition" "$(date +%s)" "$$" > "$pending"
          trap 'rm -f "$pending"; refresh' EXIT
          refresh
          err="$DIR/last-error-$inst.txt"
          if ! "$CK3" "''${args[@]}" --instance="$inst" > /dev/null 2> "$err"; then
            note --urgency=critical "Conveyor VM $inst: ''${args[*]} failed" "$(grep -v '^\s*$' "$err" | tail -n 1)"
          fi
          ;;

        _drain) # the only thing allowed to stop the VM on its own
          printf '{"transition":"draining","since":%s,"pid":%s}\n' "$(date +%s)" "$$" > "$pending"
          trap 'rm -f "$pending"; refresh; exit 0' TERM INT
          trap 'rm -f "$pending"; refresh' EXIT
          refresh
          while true; do
            n="$("$CK3" vm pods --instance="$inst" 2>/dev/null \
              | python3 -c 'import json,sys; t=sys.stdin.read(); d=json.loads(t[t.find("{"):]); print(sum(1 for p in d.get("pods",[]) if p.get("phase") in ("Running","Pending")))' \
              2>/dev/null || echo unknown)"
            if [ "$n" = 0 ]; then
              printf '{"transition":"stopping","since":%s,"pid":%s}\n' "$(date +%s)" "$$" > "$pending"
              refresh
              if "$CK3" vm stop --instance="$inst" > /dev/null 2> "$DIR/last-error-$inst.txt"; then
                note "Conveyor VM $inst stopped after the last card"
              else
                note --urgency=critical "Conveyor VM $inst: stop failed" "$(grep -v '^\s*$' "$DIR/last-error-$inst.txt" | tail -n 1)"
              fi
              exit 0
            fi
            sleep 30 &
            wait $!
          done
          ;;
        *) usage ;;
      esac
    '';
  };
in {
  home.packages = [status ctl];

  systemd.user.services.qs-conveyor-vm-status = {
    Unit = {
      Description = "Conveyor Personal Compute VM state for the Quickshell bar pill";
      # Only hosts that have created an instance; elsewhere no file, no pill.
      ConditionPathIsDirectory = "%h/.local/share/conveyor-k3-vms";
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe status;
    };
  };

  systemd.user.timers.qs-conveyor-vm-status = {
    Unit.Description = "Refresh the Conveyor VM pill";
    Timer = {
      OnStartupSec = "20s";
      OnUnitActiveSec = "${toString intervalSec}s";
      AccuracySec = "2s";
    };
    Install.WantedBy = ["timers.target"];
  };
}

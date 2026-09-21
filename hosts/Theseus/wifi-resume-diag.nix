# Resume-time network capture for the "wifi connected, nothing resolves"
# symptom. Instruments only -- the fix is a separate card.
#
# WHAT IT CATCHES: after resume tailscaled recompiles DNS the instant the
# default route appears (wgengine linkChange -> dns.Set -> openresolv
# GetBaseConfig). If NetworkManager has not yet run `resolvconf -a
# NetworkManager`, the upstream list is empty and every lookup is SERVFAIL
# until the next link change. This module records, from three vantage
# points, what resolvconf held at each moment:
#   - the systemd-sleep hook (pre/post snapshots),
#   - the NetworkManager dispatcher (one line per NM event),
#   - a bounded 90 s post-resume sampler launched as its own transient unit.
# Everything lands under /var/log/wifi-resume-diag/<stamp>-<op>/ with a
# verdict.txt a human reads while the network is dead.
#
# HARD RULES: the sleep hook must never block or fail suspend; every probe is
# bounded and `|| true`; nothing here changes NM or tailscale state; no
# network calls beyond the local `getent` probe. The sampler MUST be started
# with systemd-run -- a child backgrounded with `&` from a system-sleep hook
# lives in systemd-suspend*.service's cgroup and dies when the unit stops.
# systemd-sleep's and the dispatcher's PATHs are minimal, so every binary
# must come from runtimeInputs (see hibernate.nix for the same lesson).
#
# PERSONAL DATA: the capture dirs and the INFO-level NM journal carry SSIDs,
# MACs, LAN addresses and the tailnet name. They stay on local disk. Card
# chat and commits get redacted excerpts only.
{pkgs, ...}: let
  iface = "wlp192s0";
  root = "/var/log/wifi-resume-diag";

  wifiResumeDiag = pkgs.writeShellApplication {
    name = "wifi-resume-diag";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gawk
      gnused
      iproute2
      networkmanager
      openresolv
      tailscale
      systemd
      util-linux
      procps
      glibc # getent
    ];
    text = ''
      set -euo pipefail
      ROOT=${root}
      IFACE=${iface}

      section() { printf '\n=== %s  %s ===\n' "$1" "$(date -Is)"; }

      # One full picture of resolver + link state. Every probe || true: a
      # snapshot that dies on its third command tells you nothing about the
      # fourth.
      snapshot() {
        local dir="$1" label="$2" out
        out="$dir/$label.txt"
        {
          section "resolvconf -i";    resolvconf -i 2>&1 || true
          section "resolvconf -l";    resolvconf -l 2>&1 || true
          section "/etc/resolv.conf"; cat /etc/resolv.conf 2>&1 || true
          section "nmcli device";     nmcli -t -f GENERAL.STATE,GENERAL.CONNECTION,GENERAL.REASON,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP4.DOMAIN device show "$IFACE" 2>&1 || true
          section "nmcli general";    nmcli -t general status 2>&1 || true
          section "ip -4 addr";       ip -4 addr show "$IFACE" 2>&1 || true
          section "ip -4 route";      ip -4 route 2>&1 || true
          section "ip -6 route";      ip -6 route 2>&1 | head -20 || true
          section "tailscale dns status"; timeout 5 tailscale dns status 2>&1 || true
          section "tailscale status --self"; timeout 5 tailscale status --self --json 2>&1 | head -c 4000 || true
          section "operstate";        cat "/sys/class/net/$IFACE/operstate" 2>&1 || true
          section "/proc/net/wireless"; cat /proc/net/wireless 2>&1 || true
        } >"$out" 2>&1 || true
      }

      # Append only when the value changed: a per-second poll that logged
      # every sample would bury the one transition that matters.
      watch_state() {
        {
          resolvconf -i 2>/dev/null || true
          echo "--"
          resolvconf -l 2>/dev/null || true
          echo "--"
          cat /etc/resolv.conf 2>/dev/null || true
          echo "--"
          nmcli -t -f GENERAL.STATE,IP4.DNS device show "$IFACE" 2>/dev/null || true
        }
      }

      cmd_pre() {
        local op="$1" dir
        dir="$ROOT/$(date +%Y%m%dT%H%M%S)-$op"
        mkdir -p "$dir"
        date -Is >"$dir/pre.ts"
        ln -sfn "$dir" "$ROOT/latest"
        snapshot "$dir" pre
      }

      cmd_post() {
        local dir
        dir="$(readlink -f "$ROOT/latest" 2>/dev/null || true)"
        [ -n "$dir" ] && [ -d "$dir" ] || exit 0
        snapshot "$dir" post-0
        # Outlives this hook: systemd-run puts it in its own unit.
        systemd-run --unit "wifi-resume-diag-$(basename "$dir")" --collect --quiet \
          --property=Type=exec \
          "$0" sample "$dir" || true
      }

      cmd_sample() {
        local dir="$1" prev="" cur i
        for i in $(seq 1 90); do
          cur="$(watch_state)"
          if [ "$cur" != "$prev" ]; then
            { printf '=== %s ===\n' "$(date -Is)"; printf '%s\n' "$cur"; } >>"$dir/samples.log"
            prev="$cur"
          fi
          if [ $((i % 10)) -eq 1 ]; then
            {
              printf '=== %s ===\n' "$(date -Is)"
              if getent hosts example.com 2>&1; then echo "getent rc=0"; else echo "getent rc=$?"; fi
              timeout 2 tailscale dns status 2>&1 | head -30 || true
            } >>"$dir/probes.log"
          fi
          sleep 1
        done
        write_verdict "$dir"
      }

      write_verdict() {
        local dir="$1" since resume_ts broken_line nm_ts
        since="$(cat "$dir/pre.ts" 2>/dev/null || date -Is -d '-10 minutes')"
        journalctl -o short-iso --since "$since" -k \
          -u NetworkManager -u tailscaled -u wpa_supplicant -u sleep-actions \
          -u systemd-suspend -u systemd-suspend-then-hibernate -u systemd-hibernate \
          >"$dir/journal.log" 2>&1 || true

        resume_ts="$(grep -E 'PM: suspend exit|hibernation exit|PM: hibernation exit' "$dir/journal.log" | tail -1 | awk '{print $1}' || true)"
        # The tell: an empty upstream list compiled AFTER the resume line.
        broken_line="$(awk -v r="$resume_ts" 'r != "" && $1 > r && /dns: Resolvercfg: \{Routes:\{\.:\[\]/ {print; exit}' "$dir/journal.log" || true)"
        # resolvconf -l prints each interface's block under "# resolv.conf from <iface>".
        nm_ts="$(awk '/^=== /{ts=$2} /^# resolv.conf from NetworkManager/{nm=1; next} /^# resolv.conf from/{nm=0} /^--$/{nm=0} nm && /^nameserver/{print ts; exit}' "$dir/samples.log" 2>/dev/null || true)"

        {
          if [ -z "$resume_ts" ]; then
            echo "UNKNOWN: no resume line in journal.log (not a sleep cycle?)"
          elif [ -n "$broken_line" ]; then
            echo "BROKEN"
            echo "resume:            $resume_ts"
            echo "empty upstream at: $(echo "$broken_line" | awk '{print $1}')"
            echo "NM nameserver seen in resolvconf -l at: ''${nm_ts:-never during the 90 s sample}"
            echo
            echo "$broken_line"
          elif grep -q 'dns: Resolvercfg' "$dir/journal.log"; then
            echo "OK"
            echo "resume:            $resume_ts"
            echo "NM nameserver seen in resolvconf -l at: ''${nm_ts:-not observed}"
          else
            echo "UNKNOWN: no Resolvercfg line from tailscaled after resume"
          fi
        } >"$dir/verdict.txt"
      }

      # Dispatcher hook: runs for EVERY NM event on EVERY interface. O(1),
      # always exit 0.
      cmd_nm_event() {
        local ifc="''${1:-?}" action="''${2:-?}" out
        if [ -e "$ROOT/latest" ]; then out="$ROOT/latest/nm-events.log"; else out="$ROOT/nm-events-idle.log"; fi
        printf '%s iface=%s action=%s ifaces=[%s] nm_dns=[%s]\n' \
          "$(date -Is)" "$ifc" "$action" \
          "$(resolvconf -i 2>/dev/null | tr '\n' ' ' || true)" \
          "$(nmcli -t -f IP4.DNS device show "$ifc" 2>/dev/null | tr '\n' ' ' || true)" \
          >>"$out" 2>/dev/null || true
      }

      cmd_last() {
        local dir
        dir="$(readlink -f "$ROOT/latest" 2>/dev/null || true)"
        if [ -z "$dir" ] || [ ! -d "$dir" ]; then echo "no capture yet"; return 0; fi
        echo "$dir"; echo
        cat "$dir/verdict.txt" 2>/dev/null || echo "(no verdict yet -- sampler still running?)"
        echo; ls -la "$dir"
      }

      case "''${1:-}" in
        pre)      cmd_pre "''${2:-unknown}" ;;
        post)     cmd_post ;;
        sample)   cmd_sample "$2" ;;
        nm-event) cmd_nm_event "''${2:-}" "''${3:-}" ;;
        last)     cmd_last ;;
        list)     ls -1 "$ROOT" 2>/dev/null || true ;;
        *)        echo "usage: wifi-resume-diag {pre <op>|post <op>|sample <dir>|nm-event <iface> <action>|last|list}" >&2; exit 2 ;;
      esac
    '';
  };
in {
  environment.systemPackages = [wifiResumeDiag];

  # systemd-sleep passes `pre|post` then `suspend|hibernate|suspend-then-hibernate`.
  # Anything else falls through to exit 0 -- this hook may never fail sleep.
  environment.etc."systemd/system-sleep/wifi-resume-diag" = {
    mode = "0755";
    source = pkgs.writeShellScript "wifi-resume-diag-sleep" ''
      case "''${1:-}" in
        pre|post) exec ${wifiResumeDiag}/bin/wifi-resume-diag "$1" "''${2:-unknown}" ;;
        *) exit 0 ;;
      esac
    '';
  };

  networking.networkmanager.dispatcherScripts = [
    {
      source = pkgs.writeShellScript "wifi-resume-diag-nm" ''
        exec ${wifiResumeDiag}/bin/wifi-resume-diag nm-event "''${1:-}" "''${2:-}"
      '';
      type = "basic";
    }
  ];

  # NixOS default is WARN, which is why the journal has no NM DNS/device
  # lines at all. Theseus only, by virtue of living in this host module.
  networking.networkmanager.logLevel = "INFO";

  systemd.tmpfiles.rules = ["d ${root} 0755 root root 30d"];
}

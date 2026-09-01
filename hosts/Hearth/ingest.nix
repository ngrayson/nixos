# H8 routing: hardlink new Syncthing arrivals from /mnt/cold/share into the
# Jellyfin library at /mnt/cold/media, then write sidecars for each new video.
# Five-minute timer, not a .path unit — arrivals are nested
# (share/tv/<Show>/Season 01/<file>) and .path units are not recursive.
#
# Hardlink, never move. /mnt/cold/share is a Syncthing receiveonly folder
# (see syncthing.nix): moving a file out of one leaves it permanently
# out-of-sync, and Syncthing's only offered remedy re-downloads the whole
# folder. Nothing here writes to share/ at all.
{
  lib,
  pkgs,
  ...
}: let
  # Gated on the file existing, the same way syncthing.nix gates on
  # hearth-seedbox.yaml: Hearth must keep evaluating before Nick has minted the
  # key, and until then ingest simply leaves discovery to Jellyfin's own scan.
  jellyfinSecrets = ../../secrets/hearth-jellyfin.yaml;
  haveJellyfinKey = builtins.pathExists jellyfinSecrets;

  hearth-ingest = pkgs.writeShellApplication {
    name = "hearth-ingest";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.findutils
      pkgs.python3
    ];
    text = ''
      set -euo pipefail

      usage() {
        cat <<'EOF'
      hearth-ingest — hardlink new seedbox arrivals into the Jellyfin library.

      Usage:
        hearth-ingest [--dry-run] [--no-sidecars] [SHARE_ROOT ...]

      Default share root: /mnt/cold/share   Library root: /mnt/cold/media
      Routed top-level dirs: movies, tv, music. Anything else stays put.

      Hardlinks only — never moves, renames or deletes inside share/.
      Idempotent: an existing destination on the same inode is skipped, and a
      different file at the destination is logged as a conflict, never
      overwritten. Sequential, nice + ionice -c3: COLD is one USB disk that is
      also serving playback.
      EOF
      }

      # Overridable so the routing logic can be exercised off-box against a
      # scratch tree; the unit below sets neither and gets the real paths.
      LIBRARY_ROOT="''${HEARTH_INGEST_LIBRARY_ROOT:-/mnt/cold/media}"
      LEDGER="''${HEARTH_INGEST_LEDGER:-/run/hearth-intranet/ingest.json}"
      DRY=0
      SIDECARS=1
      ROOTS=()

      while [[ $# -gt 0 ]]; do
        case "$1" in
          -h|--help) usage; exit 0 ;;
          --dry-run) DRY=1; shift ;;
          --no-sidecars) SIDECARS=0; shift ;;
          --) shift; ROOTS+=("$@"); break ;;
          -*) echo "hearth-ingest: unknown flag $1" >&2; usage >&2; exit 2 ;;
          *) ROOTS+=("$1"); shift ;;
        esac
      done
      if [[ ''${#ROOTS[@]} -eq 0 ]]; then
        ROOTS=(/mnt/cold/share)
      fi

      # ionice is best-effort: missing privilege still runs.
      ionice -c3 -p $$ >/dev/null 2>&1 || true
      renice -n 19 $$ >/dev/null 2>&1 || true

      is_video() {
        case "''${1,,}" in
          *.mkv|*.mp4|*.m4v|*.avi|*.mov|*.webm) return 0 ;;
          *) return 1 ;;
        esac
      }

      # Records for the ledger, one TSV line each: result/src/dest/library.
      # A temp file rather than an array: the run may legitimately produce zero
      # records, and feeding an empty array to a pipeline under `set -u` is a
      # trap with no upside here.
      RECORD_FILE="$(mktemp)"
      trap 'rm -f "$RECORD_FILE"' EXIT
      note() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$RECORD_FILE"; }

      link_one() {
        local src="$1" library="$2" rel="$3" dest="$4"

        if [[ -e "$dest" ]]; then
          if [[ "$(stat -c %i "$src")" == "$(stat -c %i "$dest")" ]]; then
            note skipped "$src" "$dest" "$library"
          else
            echo "hearth-ingest: conflict, different file already at $dest" >&2
            note conflict "$src" "$dest" "$library"
          fi
          return 0
        fi

        echo "LINK	$rel"
        if [[ "$DRY" -eq 1 ]]; then
          note dry-run "$src" "$dest" "$library"
          return 0
        fi

        # Never chown/chmod on COLD: it is NTFS mounted uid=0 gid=989
        # umask=0002, so ownership comes from the mount options and chmod(2)
        # returns EPERM. mkdir -p and link(2) are all that is needed.
        if ! mkdir -p "$(dirname "$dest")" || ! ln "$src" "$dest"; then
          echo "hearth-ingest: failed to link $src -> $dest" >&2
          note error "$src" "$dest" "$library"
          return 0
        fi
        note linked "$src" "$dest" "$library"

        if [[ "$SIDECARS" -eq 1 ]] && is_video "$dest"; then
          # Reuse the H3 one-shot extractor rather than writing a second one.
          # It reaches us through environment.systemPackages, hence the
          # /run/current-system/sw entry on the unit's path below. A failure
          # here must never fail the run: the hardlink already succeeded, and
          # Bazarr's upstream .srt is the durable caption fix anyway.
          if command -v hearth-extract-sidecars >/dev/null 2>&1; then
            hearth-extract-sidecars --one "$dest" ||
              echo "hearth-ingest: sidecar extract failed for $dest" >&2
          else
            echo "hearth-ingest: hearth-extract-sidecars not on PATH, skipped $dest" >&2
          fi
        fi
      }

      for share in "''${ROOTS[@]}"; do
        if [[ ! -d "$share" ]]; then
          echo "hearth-ingest: skip missing share root $share" >&2
          continue
        fi
        for libdir in "$share"/*; do
          [[ -d "$libdir" ]] || continue
          library="$(basename "$libdir")"
          case "$library" in
            movies|tv|music) ;;
            *)
              echo "hearth-ingest: unrouted top-level dir $library, leaving in place" >&2
              note unknown-library "$libdir" "" "$library"
              continue
              ;;
          esac

          # Syncthing renames its temp file into place only once a transfer
          # finishes, so a fully-named file is a finished file.
          while IFS= read -r -d $'\0' src; do
            rel="''${src#"$share"/}"
            link_one "$src" "$library" "$rel" "$LIBRARY_ROOT/$rel"
          done < <(find "$libdir" -type f \
            -not -path '*/.stfolder/*' \
            -not -path '*/.stversions/*' \
            -not -name '.stignore' \
            -not -name '.syncthing.*.tmp' \
            -print0)
        done
      done

      if [[ "$DRY" -eq 1 ]]; then
        exit 0
      fi

      # Tell Jellyfin about exactly the files that just landed, instead of
      # leaving discovery to its periodic full "Scan All Libraries".
      #
      # COLD is ntfs-3g/FUSE, which does not deliver the inotify events
      # Jellyfin's real-time monitor relies on, so without this a new episode
      # only shows up on the next scheduled scan. POST /Library/Media/Updated
      # is the endpoint built for this, and the same one the *arr ecosystem's
      # own Jellyfin notifications use.
      #
      # One request per run carrying every new path, not one per file. Fails
      # open in every direction: no key, Jellyfin down, bad response — the
      # hardlinks and sidecars already succeeded, and the scheduled scan
      # remains the safety net it always was.
      python3 - "$RECORD_FILE" <<'PY'
      import json, os, sys, urllib.error, urllib.request

      record_file = sys.argv[1]
      key_file = os.environ.get(
          "HEARTH_JELLYFIN_KEY_FILE", "/run/secrets/hearth-jellyfin-api-key")
      base = os.environ.get("HEARTH_JELLYFIN_URL", "http://127.0.0.1:8096").rstrip("/")


      def log(msg):
          print(f"hearth-ingest: {msg}", file=sys.stderr, flush=True)


      def note(result, detail):
          # Same TSV shape the shell's note() writes; the ledger step below
          # reads this file straight after us.
          with open(record_file, "a", encoding="utf-8") as fh:
              fh.write(f"{result}\t{detail}\t\t\n")


      with open(record_file, encoding="utf-8") as fh:
          rows = [line.split("\t") for line in fh.read().splitlines() if line.strip()]

      paths = [r[2] for r in rows if r and r[0] == "linked" and len(r) > 2 and r[2]]
      if not paths:
          sys.exit(0)

      try:
          with open(key_file, encoding="utf-8") as fh:
              key = fh.read().strip()
      except OSError:
          log("no Jellyfin API key readable; leaving discovery to its scheduled scan")
          sys.exit(0)
      if not key:
          log("Jellyfin API key file is empty; skipping notify")
          sys.exit(0)

      body = json.dumps(
          {"Updates": [{"Path": p, "UpdateType": "Created"} for p in paths]}
      ).encode("utf-8")
      req = urllib.request.Request(
          f"{base}/Library/Media/Updated",
          data=body,
          method="POST",
          headers={
              "Content-Type": "application/json",
              # Header, never the query string: a token in a URL ends up in
              # access logs.
              "X-Emby-Token": key,
              "User-Agent": "hearth-ingest",
          },
      )
      try:
          with urllib.request.urlopen(req, timeout=15) as resp:
              resp.read()
      except urllib.error.HTTPError as exc:
          # Never log the key, and the URL carries none.
          log(f"Jellyfin notify failed: HTTP {exc.code}")
          note("notify-error", f"HTTP {exc.code}")
          sys.exit(0)
      except Exception as exc:
          log(f"Jellyfin notify failed: {type(exc).__name__}")
          note("notify-error", type(exc).__name__)
          sys.exit(0)

      log(f"told Jellyfin about {len(paths)} new file(s)")
      PY

      # Ledger for the homepage Ingest widget. Rewritten every run, atomically,
      # carrying the previous run's recent entries forward.
      python3 - "$LEDGER" "$RECORD_FILE" <<'PY'
      import json, os, sys, time

      out, record_file = sys.argv[1], sys.argv[2]
      now = int(time.time())

      with open(record_file, encoding="utf-8") as fh:
          records = fh.read().splitlines()

      fresh, pending, errors = [], [], []
      for line in records:
          if not line.strip():
              continue
          result, src, dest, library = (line.split("\t") + ["", "", "", ""])[:4]
          entry = {"src": src, "dest": dest, "library": library,
                   "at": now, "result": result}
          if result in ("linked", "skipped"):
              fresh.append(entry)
          elif result == "conflict":
              pending.append(entry)
              errors.append(f"conflict: {dest} exists and is a different file")
          elif result == "unknown-library":
              pending.append(entry)
              errors.append(f"unrouted top-level dir: {library}")
          elif result == "error":
              pending.append(entry)
              errors.append(f"link failed: {src} -> {dest}")
          elif result == "notify-error":
              # The files did land; only telling Jellyfin failed, so this is a
              # visible warning rather than something pending action.
              errors.append(f"jellyfin notify failed: {src}")

      previous = []
      try:
          with open(out, encoding="utf-8") as fh:
              previous = json.load(fh).get("recent") or []
      except (OSError, ValueError):
          previous = []

      payload = {
          "pending": pending,
          "recent": (fresh + previous)[:25],
          "errors": errors,
          "generatedAt": now,
      }
      os.makedirs(os.path.dirname(out), exist_ok=True)
      tmp = out + ".tmp"
      with open(tmp, "w", encoding="utf-8") as fh:
          json.dump(payload, fh)
          fh.write("\n")
      os.chmod(tmp, 0o644)
      os.replace(tmp, out)
      PY
    '';
  };
in {
  environment.systemPackages = [hearth-ingest];

  # Read by hearth-ingest as the identity the unit already runs as. The key is
  # a Jellyfin API key from Dashboard -> API Keys; it is never in git.
  sops.secrets = lib.mkIf haveJellyfinKey {
    hearth-jellyfin-api-key = {
      sopsFile = jellyfinSecrets;
      key = "api_key";
      owner = "wiz";
      group = "jellyfin";
      mode = "0440";
    };
  };

  systemd.services.hearth-ingest = {
    description = "Hardlink new Syncthing arrivals into the Jellyfin library";
    after = ["mnt-cold.mount" "local-fs.target"];
    wants = ["mnt-cold.mount"];
    unitConfig.RequiresMountsFor = ["/mnt/cold"];
    serviceConfig = {
      Type = "oneshot";
      # Same identity services.syncthing runs as (syncthing.nix): COLD is
      # mounted uid=0 gid=989 umask=0002, so group jellyfin is what makes the
      # volume writable at all.
      User = "wiz";
      Group = "jellyfin";
      ExecStart = "${hearth-ingest}/bin/hearth-ingest";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    # hearth-extract-sidecars is installed by extract-sidecars.nix into
    # environment.systemPackages, so the running system profile is how this
    # unit reaches it.
    path = ["/run/current-system/sw"];
  };

  systemd.timers.hearth-ingest = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      AccuracySec = "30s";
      Unit = "hearth-ingest.service";
    };
  };
}

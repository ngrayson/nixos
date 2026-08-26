# One-shot sidecar extract for Hearth's library. No timer — run by hand
# (or later from H8 ingest via --one). See plan.md H3.
{pkgs, ...}: let
  hearth-extract-sidecars = pkgs.writeShellApplication {
    name = "hearth-extract-sidecars";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.ffmpeg
      pkgs.python3
      pkgs.findutils
    ];
    text = ''
      set -euo pipefail

      usage() {
        cat <<'EOF'
      hearth-extract-sidecars — write text subtitle sidecars next to media.

      Usage:
        hearth-extract-sidecars [--dry-run] [--one FILE]
        hearth-extract-sidecars [--dry-run] [ROOT ...]

      Defaults roots: /mnt/cold/media/tv /mnt/cold/media/movies
      Text tracks only (ass/ssa/subrip/mov_text/webvtt/text). Skips PGS/DVD.
      Idempotent: skip when the sidecar exists and is newer than the container.
      Sequential, nice + ionice -c3. Do not run while someone is watching.
      EOF
      }

      DRY=0
      ONE=""
      ROOTS=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -h|--help) usage; exit 0 ;;
          --dry-run) DRY=1; shift ;;
          --one)
            [[ $# -ge 2 ]] || { echo "hearth-extract-sidecars: --one needs a file" >&2; exit 2; }
            ONE="$2"
            shift 2
            ;;
          --) shift; ROOTS+=("$@"); break ;;
          -*) echo "hearth-extract-sidecars: unknown flag $1" >&2; usage >&2; exit 2 ;;
          *) ROOTS+=("$1"); shift ;;
        esac
      done

      if [[ -n "$ONE" && ''${#ROOTS[@]} -gt 0 ]]; then
        echo "hearth-extract-sidecars: --one cannot be combined with roots" >&2
        exit 2
      fi
      if [[ -z "$ONE" && ''${#ROOTS[@]} -eq 0 ]]; then
        ROOTS=(/mnt/cold/media/tv /mnt/cold/media/movies)
      fi

      plan_one() {
        python3 - "$1" <<'PY'
      import json, os, sys, subprocess

      path = sys.argv[1]
      try:
          raw = subprocess.check_output(
              [
                  "ffprobe",
                  "-v",
                  "error",
                  "-print_format",
                  "json",
                  "-show_streams",
                  "-select_streams",
                  "s",
                  path,
              ],
              text=True,
          )
      except subprocess.CalledProcessError:
          print(f"PROBE_FAIL\t{path}", flush=True)
          sys.exit(0)

      data = json.loads(raw or "{}")
      streams = data.get("streams") or []
      text = {
          "ass": "ass",
          "ssa": "ass",
          "subrip": "srt",
          "srt": "srt",
          "mov_text": "srt",
          "webvtt": "srt",
          "text": "srt",
      }
      image = {
          "hdmv_pgs_subtitle",
          "pgssub",
          "dvd_subtitle",
          "dvdsub",
          "xsub",
          "dvb_subtitle",
      }
      base, _ext = os.path.splitext(path)
      seen_lang = set()
      for stream in streams:
          codec = (stream.get("codec_name") or "").lower()
          if codec in image or codec not in text:
              continue
          idx = stream.get("index")
          tags = stream.get("tags") or {}
          lang = (tags.get("language") or tags.get("LANGUAGE") or "und").lower()
          disp = stream.get("disposition") or {}
          default = int(disp.get("default") or 0) == 1
          ext = text[codec]
          if default and (lang, ext) not in seen_lang:
              dest = f"{base}.{lang}.default.{ext}"
          elif (lang, ext) not in seen_lang and not default:
              dest = f"{base}.{lang}.{ext}"
          else:
              dest = f"{base}.{lang}.{idx}.{ext}"
          seen_lang.add((lang, ext))
          exists = os.path.exists(dest)
          newer = exists and os.path.getmtime(dest) >= os.path.getmtime(path)
          action = "SKIP" if newer else "WRITE"
          print(f"{action}\t{idx}\t{codec}\t{lang}\t{dest}", flush=True)
      PY
      }

      extract_one() {
        local file="$1" line action idx dest
        while IFS= read -r line; do
          case "$line" in
            PROBE_FAIL*) echo "$line"; continue ;;
          esac
          action="''${line%%$'\t'*}"
          dest="''${line##*$'\t'}"
          idx="$(printf '%s\n' "$line" | cut -f2)"
          echo "$line"
          if [[ "$action" != "WRITE" ]]; then
            continue
          fi
          if [[ "$DRY" -eq 1 ]]; then
            continue
          fi
          ffmpeg -hide_banner -loglevel error -nostdin -y \
            -i "$file" -map "0:$idx" -an -vn -c:s copy "$dest"
        done < <(plan_one "$file")
      }

      run_file() {
        extract_one "$1"
      }

      # ionice is best-effort: missing privilege still runs.
      ionice -c3 -p $$ >/dev/null 2>&1 || true
      renice -n 19 $$ >/dev/null 2>&1 || true

      if [[ -n "$ONE" ]]; then
        [[ -f "$ONE" ]] || { echo "hearth-extract-sidecars: not a file: $ONE" >&2; exit 2; }
        run_file "$ONE"
        exit 0
      fi

      for root in "''${ROOTS[@]}"; do
        if [[ ! -d "$root" ]]; then
          echo "hearth-extract-sidecars: skip missing root $root" >&2
          continue
        fi
        find "$root" -type f \( \
          -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.m4v' \
          -o -iname '*.avi' -o -iname '*.mov' -o -iname '*.webm' \
        \) -print0 | while IFS= read -r -d $'\0' file; do
          run_file "$file"
        done
      done
    '';
  };
in {
  environment.systemPackages = [hearth-extract-sidecars];
}

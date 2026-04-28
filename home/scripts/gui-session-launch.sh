#!/usr/bin/env bash
# Tee GUI stdout/stderr to GUI_SESSION_STDIO_LOG for debugging Albert/Electron launches.
set -euo pipefail
log="${GUI_SESSION_STDIO_LOG:-/dev/null}"
exec >>"$log" 2>&1
exec "$@"

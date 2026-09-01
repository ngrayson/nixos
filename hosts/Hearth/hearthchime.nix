# Shared Hearthchime (Discord webhook) poster for Hearth's alert modules.
#
# NOT a NixOS module — do not add it to an `imports` list. It is a function
# returning a package, used as:
#
#   hearthchimePost = import ./hearthchime.nix {inherit pkgs;};
#
# A module wrapper would have nothing to own: the `hearth-discord-webhook`
# sops secret is already declared centrally in common/sops.nix (owner wiz,
# mode 0400), so anything calling this must run as wiz to read it.
#
# Exists because this is the third place in the repo that posts to the same
# webhook — hearth-notify, weather-alert.nix, and now battery-alert.nix, with
# the Go3 battery check-in card queued behind it. weather-alert.nix keeps its
# own inline POST: it is embedded in a working Python script and rewriting it
# to shell out would be churn on code nothing is asking to change.
#
# Fails open on every path, like the rest: an alert that cannot be delivered
# must never take its caller's unit down with it.
{pkgs}:
pkgs.writeShellApplication {
  name = "hearth-hearthchime-post";
  runtimeInputs = [pkgs.coreutils pkgs.curl pkgs.jq];
  text = ''
    set -euo pipefail

    msg="''${1:-}"
    if [[ -z "$msg" ]]; then
      echo "hearth-hearthchime-post: empty message; nothing to send" >&2
      exit 0
    fi

    webhook_file="''${HEARTH_NOTIFY_WEBHOOK_FILE:-/run/secrets/hearth-discord-webhook}"
    if [[ ! -r "$webhook_file" ]]; then
      echo "hearth-hearthchime-post: webhook unreadable; skipping Discord" >&2
      exit 0
    fi
    url="$(cat "$webhook_file")"
    url="''${url//[$'\r\n']/}"
    if [[ -z "$url" ]]; then
      echo "hearth-hearthchime-post: webhook empty; skipping Discord" >&2
      exit 0
    fi

    payload="$(mktemp)"
    trap 'rm -f "$payload"' EXIT
    jq -n --arg content "$msg" '{content: $content}' >"$payload"

    # The URL goes in through --config, never as an argument: argv is readable
    # by any local user via /proc for as long as curl runs. Never echo it.
    if ! printf 'url = "%s"\n' "$url" |
      curl -sS -m 10 --config - \
        -X POST -H 'Content-Type: application/json' \
        --data-binary @"$payload" -o /dev/null; then
      echo "hearth-hearthchime-post: Discord post failed; skipping" >&2
      exit 0
    fi
  '';
}

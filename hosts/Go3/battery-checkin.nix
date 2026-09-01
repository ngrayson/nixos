# Lets Hearth read this kiosk's battery over SSH, and nothing else.
#
# Go3 holds no secrets. That is the whole point of the design: the Hearthchime
# Discord webhook stays on Hearth, and Hearth reaches in here to read a battery
# rather than Go3 reaching out to post an alert. What lands on Go3 is a *public*
# key in authorized_keys, which is not a credential.
#
# The key is pinned to a forced command, so even a leaked private half yields
# two numbers and never a shell:
#
#   command="…/go3-battery-readout",restrict ssh-ed25519 AAAA…
#
# `restrict` is the modern all-of-the-above: no port, agent or X11 forwarding,
# no PTY, no user rc. The forced command overrides whatever the client asks to
# run, so the caller's own command line is irrelevant.
#
# Deliberately NOT reusing the Tawa builder key from remote-access.nix — that
# one has full deploy and passwordless-sudo reach, and handing that scope to an
# unattended timer on another host is a far bigger blast radius than reading a
# battery needs. This is a separate, one-way trust relationship.
#
# Also deliberately not relaxing stats-server.nix's loopback-only bind. That
# boundary is documented there as hard because Go3 sits on shared household
# Wi-Fi; this routes around it over SSH instead of widening it.
#
# Until Nick generates the keypair and commits the public half, the file below
# does not exist and this module contributes nothing — the host still evaluates.
# See the PR for the three manual steps.
{
  lib,
  pkgs,
  ...
}: let
  pubKeyFile = ../../secrets/hearth-go3-checkin.pub;
  havePubKey = builtins.pathExists pubKeyFile;

  # Prints "<percent> <status>", e.g. "84 Discharging". Exits non-zero when
  # there is no system battery, which the caller reads as "no reading".
  readout = pkgs.writeShellApplication {
    name = "go3-battery-readout";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      set -euo pipefail

      SUPPLY_ROOT="''${GO3_BATTERY_SUPPLY_ROOT:-/sys/class/power_supply}"

      # Same scope=System filter as home/services/battery-notify.nix: a bare
      # type=Battery test also matches peripherals reporting scope=Device.
      for dir in "$SUPPLY_ROOT"/*; do
        [[ -r "$dir/type" ]] || continue
        [[ "$(cat "$dir/type")" == "Battery" ]] || continue
        scope="System"
        [[ -r "$dir/scope" ]] && scope="$(cat "$dir/scope")"
        [[ "$scope" == "System" ]] || continue
        [[ -r "$dir/capacity" && -r "$dir/status" ]] || continue
        printf '%s %s\n' "$(cat "$dir/capacity")" "$(cat "$dir/status")"
        exit 0
      done
      exit 1
    '';
  };
in {
  users.users.wiz.openssh.authorizedKeys.keys = lib.mkIf havePubKey [
    ''command="${readout}/bin/go3-battery-readout",restrict ${lib.removeSuffix "\n" (builtins.readFile pubKeyFile)}''
  ];
}

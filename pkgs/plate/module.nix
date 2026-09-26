# NixOS module: weekly "plate" digest (Conveyor → Discord) as a systemd timer.
#
#   services.plate = {
#     enable = true;
#     environmentFile = config.age.secrets.plate-env.path;   # or sops
#     onCalendar = "Sat 10:00";                               # host-local time
#     maxItems = 4;                                           # per-group cap before "…and N more"
#     runOnChange = true;                                     # also post when the digest package changes
#   };
#
# `plate-now` is installed as a command for on-demand runs: it starts plate.service (so the run gets the
# service's EnvironmentFile and sandbox) and prints that run's log. Needs root, like any unit start.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.plate;
  plate = pkgs.buildNpmPackage {
    pname = "plate";
    version = "0.1.0";
    # Only what the build reads, so README/module edits do not rebuild the package.
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [ ./package.json ./package-lock.json ./digest.mjs ./preload.cjs ];
    };
    npmDepsHash = "sha256-1cZoH8h0BzRsH05uFprnLqNiS2jSGDeRDz4pkqxGeog=";
    dontNpmBuild = true;
    # cv.mjs (a general-purpose Conveyor CLI) is a dev tool and stays out of the installed package.
    installPhase = ''
      mkdir -p $out/lib/plate
      cp -r digest.mjs preload.cjs package.json node_modules $out/lib/plate/
    '';
  };
  digest = pkgs.writeShellScript "plate-digest" ''
    export PLATE_MAX_ITEMS=${toString cfg.maxItems}
    exec ${pkgs.nodejs}/bin/node ${plate}/lib/plate/digest.mjs --post
  '';
  # Posts only if the installed plate package differs from the one recorded at the last post, so the
  # boot-time start of plate-on-change.service (and switches that don't touch plate) are no-ops.
  onChange = pkgs.writeShellScript "plate-on-change" ''
    stamp="$STATE_DIRECTORY/last-format"
    if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "${plate}" ]; then exit 0; fi
    ${digest} && echo "${plate}" > "$stamp"
  '';
  serviceConfig = {
    Type = "oneshot";
    DynamicUser = true;
    EnvironmentFile = cfg.environmentFile;
    # digest.md/json land in PLATE_OUT; keep the last run for a future Go3 dashboard panel.
    StateDirectory = "plate";
    WorkingDirectory = "/var/lib/plate";
    Environment = "PLATE_OUT=/var/lib/plate";
    ExecStart = digest;
    PrivateTmp = true;
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
  };
  # The secrets only exist inside the unit, so an on-demand run goes through it rather than
  # calling digest.mjs from a login shell (which would die on "missing CONVEYOR_API_URL").
  runner = pkgs.writeShellScriptBin "plate-now" ''
    since=$(date '+%Y-%m-%d %H:%M:%S')
    rc=0
    systemctl start plate.service || rc=$?
    journalctl -u plate.service --since "$since" --no-pager -o cat
    exit $rc
  '';
in
{
  options.services.plate = {
    enable = lib.mkEnableOption "weekly Conveyor plate digest to Discord";
    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = "File with CONVEYOR_API_URL, CONVEYOR_USER_TOKEN, CONVEYOR_PROJECT_ID, DISCORD_WEBHOOK_URL and optionally NOTION_TOKEN (KEY=value lines). Keep it in secrets/.";
    };
    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "Sat 10:00";
      description = "systemd OnCalendar expression, host-local time.";
    };
    maxItems = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Max line items per group in the digest before collapsing to \"…and N more\".";
    };
    runOnChange = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Also post a digest during activation whenever the plate package (digest.mjs or deps) changes.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ runner ];

    systemd.services.plate = {
      description = "Plate digest: Conveyor + Notion → Discord";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # digest.mjs spawns the Conveyor MCP server as a bare `node` child process.
      path = [ pkgs.nodejs ];
      inherit serviceConfig;
    };

    # Fires during a switch in which the plate package changed (new digest format, dep bump).
    # RemainAfterExit keeps it "active" so the changed restartTrigger restarts (= re-runs) it;
    # the stamp check inside makes boot-time starts and unrelated switches no-ops.
    systemd.services.plate-on-change = lib.mkIf cfg.runOnChange {
      description = "Plate digest: post on format change";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.nodejs ];
      restartTriggers = [ plate ];
      serviceConfig = serviceConfig // {
        RemainAfterExit = true;
        ExecStart = onChange;
      };
    };

    systemd.timers.plate = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;   # catch up if Hearth was asleep at 10:00
        RandomizedDelaySec = "2m";
      };
    };
  };
}

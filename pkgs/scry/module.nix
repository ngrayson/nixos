# NixOS module: the Scrying Orb — weekly "scry" digest (Conveyor + Notion → Discord) as a systemd timer.
#
#   services.scry = {
#     enable = true;
#     environmentFile = config.age.secrets.scry-env.path;   # or sops
#     onCalendar = "Sat 10:00";                               # host-local time
#     maxItems = 4;                                           # per-group cap before "…and N more"
#     runOnChange = true;                                     # also post when the digest package changes
#   };
#
# `scry-now` is installed as a command for on-demand runs: it starts scry.service (so the run gets the
# service's EnvironmentFile and sandbox) and prints that run's log. Needs root, like any unit start.
#
# `scry-task <text>` files one row in Nick's Tasks (Notion) from inbox-grammar text (task.mjs) and
# prints its URL; hearth-tui's "Scry — file a task" calls it over ssh. Also root, for the same reason.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.scry;
  scry = pkgs.buildNpmPackage {
    pname = "scry";
    version = "0.1.0";
    # Only what the build reads, so README/module edits do not rebuild the package.
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [ ./package.json ./package-lock.json ./digest.mjs ./task.mjs ./preload.cjs ];
    };
    npmDepsHash = "sha256-FZA+we/8wPU8fJHLD9K9BHICPB7h9jGgJtNoRIBpF5E=";
    dontNpmBuild = true;
    # cv.mjs (a general-purpose Conveyor CLI) is a dev tool and stays out of the installed package.
    installPhase = ''
      mkdir -p $out/lib/scry
      cp -r digest.mjs task.mjs preload.cjs package.json node_modules $out/lib/scry/
    '';
  };
  digest = pkgs.writeShellScript "scry-digest" ''
    export SCRY_MAX_ITEMS=${toString cfg.maxItems}
    exec ${pkgs.nodejs}/bin/node ${scry}/lib/scry/digest.mjs --post
  '';
  # Posts only if the installed scry package differs from the one recorded at the last post, so the
  # boot-time start of scry-on-change.service (and switches that don't touch scry) are no-ops.
  onChange = pkgs.writeShellScript "scry-on-change" ''
    stamp="$STATE_DIRECTORY/last-format"
    if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "${scry}" ]; then exit 0; fi
    ${digest} && echo "${scry}" > "$stamp"
  '';
  serviceConfig = {
    Type = "oneshot";
    DynamicUser = true;
    EnvironmentFile = cfg.environmentFile;
    # digest.md/json land in SCRY_OUT; keep the last run for a future Go3 dashboard panel.
    StateDirectory = "scry";
    WorkingDirectory = "/var/lib/scry";
    Environment = "SCRY_OUT=/var/lib/scry";
    ExecStart = digest;
    PrivateTmp = true;
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
  };
  # The secrets only exist inside the unit, so an on-demand run goes through it rather than
  # calling digest.mjs from a login shell (which would die on "missing CONVEYOR_API_URL").
  runner = pkgs.writeShellScriptBin "scry-now" ''
    since=$(date '+%Y-%m-%d %H:%M:%S')
    rc=0
    systemctl start scry.service || rc=$?
    journalctl -u scry.service --since "$since" --no-pager -o cat
    exit $rc
  '';
  # One row in Nick's Tasks (Notion) from inbox-grammar text. Runs in a transient unit so the
  # secret file is read by systemd as root and the node process gets the same sandbox as scry.service.
  # --pipe hands the unit's stdout/stderr back to the caller; --wait returns its exit code.
  taskRunner = pkgs.writeShellScriptBin "scry-task" ''
    [ $# -gt 0 ] || { echo "usage: scry-task <text> [p0-p3] [#area] [due:<date>] [@agent|@collab]" >&2; exit 2; }
    exec systemd-run --quiet --wait --pipe --collect \
      -p DynamicUser=yes -p EnvironmentFile=${cfg.environmentFile} \
      -p PrivateTmp=yes -p NoNewPrivileges=yes -p ProtectSystem=strict -p ProtectHome=yes \
      ${pkgs.nodejs}/bin/node ${scry}/lib/scry/task.mjs "$@"
  '';
in
{
  options.services.scry = {
    enable = lib.mkEnableOption "weekly Conveyor scry digest to Discord";
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
      description = "Also post a digest during activation whenever the scry package (digest.mjs or deps) changes.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ runner taskRunner ];

    systemd.services.scry = {
      description = "Scrying Orb: scry digest (Conveyor + Notion → Discord)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # digest.mjs spawns the Conveyor MCP server as a bare `node` child process.
      path = [ pkgs.nodejs ];
      inherit serviceConfig;
    };

    # Fires during a switch in which the scry package changed (new digest format, dep bump).
    # RemainAfterExit keeps it "active" so the changed restartTrigger restarts (= re-runs) it;
    # the stamp check inside makes boot-time starts and unrelated switches no-ops.
    systemd.services.scry-on-change = lib.mkIf cfg.runOnChange {
      description = "Scrying Orb: post the scry digest on format change";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.nodejs ];
      restartTriggers = [ scry ];
      serviceConfig = serviceConfig // {
        RemainAfterExit = true;
        ExecStart = onChange;
      };
    };

    systemd.timers.scry = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;   # catch up if Hearth was asleep at 10:00
        RandomizedDelaySec = "2m";
      };
    };
  };
}

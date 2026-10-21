# NixOS module: the Scrying Orb — weekly "scry" digest (Conveyor + Notion → Discord) as a systemd timer.
#
#   services.scry = {
#     enable = true;
#     environmentFile = config.age.secrets.scry-env.path;   # or sops
#     onCalendar = "Sat 10:00";                               # host-local time
#     maxItems = 4;                                           # per-group cap before "…and N more"
#     runOnChange = true;                                     # also post when the digest package changes
#     notifyOnFailure = true;                                 # a failed run posts a one-line notice
#   };
#
# `scry-now` is installed as a command for on-demand runs: it starts scry.service (so the run gets the
# service's EnvironmentFile and sandbox) and prints that run's log. Needs root, like any unit start.
#
# `scry-task <text>` files one row in Nick's Tasks (Notion) from inbox-grammar text (task.mjs) and
# prints its URL; hearth-tui's "Scry — file a task" calls it over ssh. Also root, for the same reason.
#
# `services.scry.bot` runs bot.mjs as scry-bot.service: a Discord gateway bot (outbound websocket,
# no inbound port) with /task, /scry and an optional inbox channel where the owner's capture-emoji
# reaction (default :crylaugh:) files a message. Needs DISCORD_BOT_TOKEN in the
# same environmentFile; the guild/owner/channel ids are not secrets and live in the host config.
#
# `notifyOnFailure` attaches OnFailure=scry-failed@<unit>.service to scry and scry-on-change: a run
# that dies posts one line to the same Discord webhook instead of failing silently for weeks (the
# Oct 2026 Notion 404 went unseen for two Saturdays). Fail-open: no webhook or a curl error exits 0.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.scry;
  scry = pkgs.buildNpmPackage {
    pname = "scry";
    version = "0.1.0";
    # Only what the build reads, so README/module edits do not rebuild the package.
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [ ./package.json ./package-lock.json ./digest.mjs ./task.mjs ./bot.mjs ./preload.cjs ];
    };
    npmDepsHash = "sha256-7j7/oa66TXH7AoI3thtzqbFskrLmbJh4+AItAlUDI2k=";
    dontNpmBuild = true;
    # cv.mjs (a general-purpose Conveyor CLI) is a dev tool and stays out of the installed package.
    installPhase = ''
      mkdir -p $out/lib/scry
      cp -r digest.mjs task.mjs bot.mjs preload.cjs package.json node_modules $out/lib/scry/
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
  # Webhook + curl only: it must not depend on Notion or Conveyor, which are what usually fail.
  # Never prints the webhook URL; any problem is a warning and exit 0 so it cannot cascade.
  failedNotice = pkgs.writeShellScript "scry-failed" ''
    unit="''${1:-scry.service}"
    if [ -z "''${DISCORD_WEBHOOK_URL:-}" ]; then
      echo "scry-failed: DISCORD_WEBHOOK_URL not set; not posting" >&2
      exit 0
    fi
    content="⚠ $unit failed on ${config.networking.hostName} — journalctl -u $unit -b --no-pager"
    payload=$(${pkgs.jq}/bin/jq -n --arg c "$content" '{content: $c, username: "Scrying Orb", flags: 4}')
    ${pkgs.curl}/bin/curl -fsS --max-time 10 -o /dev/null \
      -H 'Content-Type: application/json' -d "$payload" "$DISCORD_WEBHOOK_URL" \
      || echo "scry-failed: posting to Discord failed" >&2
    exit 0
  '';
  failureHook = lib.optionalAttrs cfg.notifyOnFailure { OnFailure = [ "scry-failed@%n.service" ]; };
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
      description = "File with CONVEYOR_API_URL, CONVEYOR_USER_TOKEN, CONVEYOR_PROJECT_ID, DISCORD_WEBHOOK_URL and optionally NOTION_TOKEN, plus DISCORD_BOT_TOKEN when bot.enable (KEY=value lines). Keep it in secrets/.";
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
    notifyOnFailure = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Post a one-line notice to DISCORD_WEBHOOK_URL when scry.service or scry-on-change.service fails.";
    };
    bot = {
      enable = lib.mkEnableOption "the Scrying Orb Discord bot (/task, /scry, inbox channel → Notion)";
      guildId = lib.mkOption {
        type = lib.types.str;
        description = "Discord server the slash commands are registered in.";
      };
      ownerId = lib.mkOption {
        type = lib.types.str;
        description = "The only Discord user allowed to file tasks or run /scry.";
      };
      inboxChannelId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Channel where a message the owner reacts to with captureEmoji becomes a task (inbox grammar). null disables inbox mode.";
      };
      captureEmoji = lib.mkOption {
        type = lib.types.str;
        default = "crylaugh";
        description = "Name of the (custom or unicode) emoji whose reaction by the owner files a message in the inbox channel.";
      };
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
      unitConfig = failureHook;
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
      unitConfig = failureHook;
      serviceConfig = serviceConfig // {
        RemainAfterExit = true;
        ExecStart = onChange;
      };
    };

    # Template instance = the failed unit's name (%n), so the notice says which run died.
    systemd.services."scry-failed@" = lib.mkIf cfg.notifyOnFailure {
      description = "Scrying Orb: report a failed %i run to Discord";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        EnvironmentFile = cfg.environmentFile;
        ExecStart = "${failedNotice} %i";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    # Long-running gateway client; Restart=always rides out Discord reconnects and Hearth's network blips.
    systemd.services.scry-bot = lib.mkIf cfg.bot.enable {
      description = "Scrying Orb: Discord bot (/task, /scry, inbox → Notion)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # /scry runs digest.mjs, which spawns the Conveyor MCP server as a bare `node` child.
      path = [ pkgs.nodejs ];
      environment = {
        DISCORD_GUILD_ID = cfg.bot.guildId;
        DISCORD_OWNER_ID = cfg.bot.ownerId;
        DISCORD_CAPTURE_EMOJI = cfg.bot.captureEmoji;
        SCRY_MAX_ITEMS = toString cfg.maxItems;
        # Its own state dir: two DynamicUser units must not share /var/lib/scry.
        SCRY_OUT = "/var/lib/scry-bot";
      } // lib.optionalAttrs (cfg.bot.inboxChannelId != null) {
        DISCORD_INBOX_CHANNEL_ID = cfg.bot.inboxChannelId;
      };
      restartTriggers = [ scry ];
      serviceConfig = {
        DynamicUser = true;
        EnvironmentFile = cfg.environmentFile;
        ExecStart = "${pkgs.nodejs}/bin/node ${scry}/lib/scry/bot.mjs";
        StateDirectory = "scry-bot";
        WorkingDirectory = "/var/lib/scry-bot";
        Restart = "always";
        RestartSec = 10;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
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

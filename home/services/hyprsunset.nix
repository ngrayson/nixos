# f.lux-style screen warmth: hyprsunset does the gamma writing, this module
# does the scheduling.
#
# Why not hyprsunset's own `profile` entries: they are fixed wall-clock
# cutovers. They cannot ramp, they know nothing about sunrise/sunset, and they
# do not re-apply after a suspend/resume (the daemon keeps whatever it last
# set). The scheduler below is a 30-second idempotent tick instead, which gets
# smoothing, geolocation and suspend-recovery for free: every tick recomputes
# the target from the clock and pushes it only when it differs.
#
# Why not gammastep/wlsunset: wlr-gamma is proven dead on Tawa's outputs --
# "Zero outputs support gamma adjustment" on AMD Navi 22/amdgpu/Hyprland
# 0.55.4, ruled out as a competing gamma client. See PR #173/#174 and the
# card `add-gammastep-for-automatic-screen-warmth-by-sunrise-sunset`.
#
# HARD CONSTRAINT: hyprsunset must be the ONLY colour-transform-matrix writer.
# Two CTM writers fight and the screen flickers between them. Nothing else in
# this repo may touch gamma, and the Quickshell bar deliberately talks to the
# control script rather than calling `hyprctl hyprsunset` itself.
#
# The three scripts (apply, ctl, bench) live in ./hyprsunset/scripts.nix so
# they can be built and exercised without evaluating a host closure -- the
# `hypr-sunset-tests` check in flake.nix imports the same file and drives the
# apply script against a scratch tree with a stub hyprctl. See AGENTS.md
# "Screen warmth".
{
  config,
  lib,
  pkgs,
  ...
}: let
  tickSec = 30;

  sunsetScripts = import ./hyprsunset/scripts.nix {inherit pkgs lib;};
  hyprSunsetApply = sunsetScripts.apply;
  hyprSunsetCtl = sunsetScripts.ctl;
  hyprSunsetBench = sunsetScripts.bench;
in {
  # hyprsunset itself: the daemon only, with no profiles. The scheduler above
  # owns every value it ever holds. --identity so a fresh start is a no-op
  # until the first tick, rather than snapping to the 6000K built-in default.
  services.hyprsunset = {
    enable = true;
    extraArgs = ["--identity"];
  };

  # bench is shipped alongside apply/ctl but is never wired to a timer: it is a
  # manual, operator-run measurement tool (see scripts.nix / AGENTS.md).
  home.packages = [hyprSunsetApply hyprSunsetCtl hyprSunsetBench];

  systemd.user.services.hypr-sunset = {
    Unit = {
      Description = "Apply scheduled screen warmth via hyprsunset";
      After = ["hyprsunset.service"];
      PartOf = [config.wayland.systemd.target];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe hyprSunsetApply;
    };
  };

  systemd.user.timers.hypr-sunset = {
    Unit.Description = "Screen warmth tick";
    Timer = {
      OnStartupSec = "10s";
      OnUnitActiveSec = "${toString tickSec}s";
      AccuracySec = "5s";
      # Resume from suspend lands mid-schedule; without this the first tick
      # after waking waits out the full interval with yesterday's colour.
      Persistent = false;
    };
    Install.WantedBy = ["timers.target"];
  };
}

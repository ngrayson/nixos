# Nightly reboot at 03:30, to keep an indefinitely-running kiosk session from
# drifting.
#
# Go3 runs exactly one Chromium under cage and never restarts it. host.nix
# already documents the memory side of this ("One Chromium left running for
# months: zram absorbs the churn and the swapfile is the leak backstop") — but
# that cushions the symptom, where a reboot clears the cause. It also resets
# anything else that accumulates over long uptimes: GPU contexts, and the
# staging-quality IPU3 camera stack README.md warns about.
#
# Nightly rather than every other day: a wall dashboard has no viewers at
# 03:30, so the cost is a minute of blank panel, while a longer gap just gives
# leaks more days to compound. If it ever does prove disruptive, this is a
# one-line OnCalendar change — deliberately not made configurable.
#
# 03:30 is local: common/base.nix sets time.timeZone to America/Vancouver.
{pkgs, ...}: {
  systemd.services.go3-scheduled-reboot = {
    description = "Nightly kiosk reboot";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl reboot";
    };
  };

  systemd.timers.go3-scheduled-reboot = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "03:30";
      # Explicitly not Persistent. A missed run — Go3 was off at 03:30 after a
      # power blip — must not reboot the wall panel the moment it comes back,
      # at whatever hour that happens to be. Wait for the next night instead.
      Persistent = false;
      AccuracySec = "1min";
      Unit = "go3-scheduled-reboot.service";
    };
  };
}

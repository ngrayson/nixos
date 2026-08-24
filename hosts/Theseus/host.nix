# Theseus (Framework laptop) — hostname, LUKS, hibernation, and host overrides.
# The Framework AMD AI 300 module is imported by flake.nix.
{pkgs, ...}: {
  imports = [
    (import ../../common/nix-maintenance.nix {
      dates = "weekly";
      deleteOlderThan = "30d";
      configurationLimit = 12;
    })
  ];

  networking.hostName = "Theseus";
  system.stateVersion = "26.05";

  # Framework ALC285: PipeWire ACP merges Capture + Internal Mic Boost into one
  # volume slider. At 100% that is +60 dB and hard-clips the DMIC into noise.
  # Lock the boost stage at 0 dB so volume only drives Capture (+30 dB max).
  # See: https://community.frame.work/t/microphone-extremely-staticy/15533
  environment.etc."alsa-card-profile/mixer/paths/analog-input-internal-mic.conf".source = pkgs.runCommand "analog-input-internal-mic.conf" {} ''
    cp ${pkgs.pipewire}/share/alsa-card-profile/mixer/paths/analog-input-internal-mic.conf "$out"
    sed -i \
      -e '/^\[Element Internal Mic Boost\]/,/^\[/{s/^volume = merge$/volume = zero/}' \
      -e '/^\[Element Int Mic Boost\]/,/^\[/{s/^volume = merge$/volume = zero/}' \
      "$out"
  '';

  # boot.initrd.luks.devices."luks-…".device = "/dev/disk/by-uuid/…";
  # boot.kernelParams = [ ];
}

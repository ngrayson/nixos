# Theseus: Framework AMD AI 300

The flake imports `nixos-hardware.nixosModules.framework-amd-ai-300-series` for this host.

Checked-in `hardware-configuration.nix` is the **real disk map**:

| Mount | UUID |
|-------|------|
| `/` (ext4) | `78da7cc6-e97a-4f75-b5c3-15c07def2efb` |
| `/boot` (vfat) | `BB07-BF1D` |
| swap (partition) | `c42d065c-1419-42c6-b230-c46632922e7f` |

Confirm on-box with `lsblk -f` and `findmnt / /boot` before treating this file as source of truth. If they disagree, replace from `nixos-generate-config` **on Theseus**. Never copy Tawa UUIDs.

## LUKS

`host.nix` has no `boot.initrd.luks.devices`. Before enabling hibernate, check `lsblk -f` for `crypto_LUKS` and either wire the real UUID or leave an explicit “unencrypted” note. Do not leave `luks-…` template comments.

## Internal microphone (ALC285)

PipeWire's ALSA card profile merges **Capture** and **Internal Mic Boost** into one volume control. At 100% that is +60 dB on the Framework DMIC and hard-clips into noise. `host.nix` overrides `analog-input-internal-mic.conf` so boost stays at 0 dB; volume then only drives Capture. After changing that, restart WirePlumber or rebuild/switch and recheck with `wpctl get-volume @DEFAULT_AUDIO_SOURCE@`.

## Enable hibernation

`hibernate.nix` derives `boot.resumeDevice` from exactly one partition-backed `swapDevices` entry and rejects swap files because those require a resume offset.

The import in `configuration.nix` is still commented (`# ./hibernate.nix`). After verifying the swap UUID on-box, uncomment it, then:

```bash
os-rebuild build --host Theseus
os-rebuild dry-activate --host Theseus
os-rebuild boot --host Theseus
```

Reboot only after reviewing the dry activation. After boot, test `systemctl hibernate` with nonessential applications closed. A normal boot remains the recovery path if resume fails. Prefer `boot`, not `switch`, for resume-device changes. From Tawa, `os-rebuild build --host Theseus` only — activate on Theseus.

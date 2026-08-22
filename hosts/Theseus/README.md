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

Unencrypted install — `host.nix` has no `boot.initrd.luks.devices`. Recheck `lsblk -f` for `crypto_LUKS` after a reinstall; if one appears, wire the real UUID (do not leave `luks-…` placeholders).

## Internal microphone (ALC285)

PipeWire's ALSA card profile merges **Capture** and **Internal Mic Boost** into one volume control. At 100% that is +60 dB on the Framework DMIC and hard-clips into noise. `host.nix` overrides `analog-input-internal-mic.conf` so boost stays at 0 dB; volume then only drives Capture. After changing that, restart WirePlumber or rebuild/switch and recheck with `wpctl get-volume @DEFAULT_AUDIO_SOURCE@`.

## Enable hibernation

`hibernate.nix` derives `boot.resumeDevice` from exactly one partition-backed `swapDevices` entry and rejects swap files because those require a resume offset.

`configuration.nix` imports `./hibernate.nix`. After verifying the swap UUID on-box:

```bash
os-rebuild build --host Theseus
os-rebuild dry-activate --host Theseus
os-rebuild boot --host Theseus
```

Reboot only after reviewing the dry activation. After boot, test `systemctl hibernate` with nonessential applications closed. A normal boot remains the recovery path if resume fails. Prefer `boot`, not `switch`, for resume-device changes. From Tawa, `os-rebuild build --host Theseus` only — activate on Theseus. Hypridle's 1800s listener is Theseus-only `suspend-then-hibernate` so it matches logind lid policy; Tawa and Hearth stay on `suspend`.

## Tailscale

`host.nix` imports `common/tailscale.nix` (same module as Tawa). After the first Theseus switch:

```bash
sudo tailscale up
```

Join tailnet `ngrayson.github`. Do not put auth keys in the flake.

## Display

`hypr/Theseus/monitors.conf` starts from the Framework 13 2880x1920 panel at scale 1.6 on `eDP-1`. On Theseus, run `hyprmon-cfg` and rebuild if the scale or connector name is wrong.

## Fingerprint

`services.fprintd.enable` is on for Theseus only. SDDM login stays password-only. After switch, enroll with `fprintd-enroll`, then confirm `fprintd-list`. sudo / polkit / lock should use the reader.

## Keyboard backlight

Quickshell's bar still talks to `chromeos::kbd_backlight` (Intel Framework path). On Theseus, check `brightnessctl -l` — if the EC device is different (`framework_laptop::kbd_backlight` or similar), say so and we will host-gate the QML device name. Panel brightness keys use `brightnessctl -c backlight`.

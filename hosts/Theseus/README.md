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

`configuration.nix` imports `hibernate.nix` so `boot.resumeDevice` is the swap partition (`c42d065c-…`). Without that, `systemctl hibernate` still writes an image and an EFI HibernateLocation, but the next boot has no `resume=` parameter: systemd tries resume too late and the kernel reports `PM: Image not found (code -22)`.

After changing this module, then:

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

**Health pill.** `home/services/tailscale-health.nix` polls `tailscale status
--json` every 10 s on a user timer. While tailscaled reports a warnable (DNS
forwarding failing, no DERP, needs login, ...) an alert pill appears next to
the wifi pill in the bar and one sticky critical notification fires; on
recovery it is replaced by a short "Tailscale healthy again". Both debounce
15 s, so the few-second flaps on every resume never show. Raw view:
`journalctl --user -u qs-tailscale-health` and
`cat $XDG_RUNTIME_DIR/tailscale-health/state.json`.

## Wifi after resume

Symptom: after resume the wifi pill says connected, raw IPs work, and nothing
resolves. Cause (triaged 2026-09-15, tailscale 1.98.10 source + journal):
tailscaled recompiles DNS the instant the default route returns, reads
NetworkManager's resolvconf entry before NM has re-registered it, gets an empty
upstream and answers SERVFAIL until the next link change. The fix is a separate
card; this host carries the instrumentation that proves the ordering.

`hosts/Theseus/wifi-resume-diag.nix` snapshots resolver/link state from the
systemd-sleep hook, logs one line per NetworkManager event, and runs a bounded
90 s sampler after resume. NetworkManager logs at INFO here (default WARN).

```bash
wifi-resume-diag last     # latest capture: verdict.txt + file list
wifi-resume-diag list     # all captures under /var/log/wifi-resume-diag
```

`verdict.txt` says `BROKEN` when tailscaled compiled an empty upstream list
after the resume line (and when, if ever, NM's nameserver appeared in
`resolvconf -l`), `OK` when it found one, `UNKNOWN` when the run was not a
sleep cycle. Reproduce: close the lid, wait 2+ minutes, open it, touch nothing
for 90 s, then `getent hosts example.com` and `wifi-resume-diag last`.

The capture directories and the INFO-level journal contain SSIDs, MACs, LAN
addresses and the tailnet name. They stay on this disk -- never paste them
into a card or a commit unredacted. Runs age out after 30 days.

## Display

`hypr/Theseus/monitors.conf` starts from the Framework 13 2880x1920 panel at scale 1.6 on `eDP-1`. On Theseus, run `hyprmon-cfg` and rebuild if the scale or connector name is wrong.

## Fingerprint

`services.fprintd.enable` is on for Theseus only. SDDM login stays password-only. After switch, enroll with `fprintd-enroll`, then confirm `fprintd-list`. sudo / polkit / lock should use the reader.

## Keyboard backlight

Quickshell's bar still talks to `chromeos::kbd_backlight` (Intel Framework path). On Theseus, check `brightnessctl -l` — if the EC device is different (`framework_laptop::kbd_backlight` or similar), say so and we will host-gate the QML device name. Panel brightness keys use `brightnessctl -c backlight`.

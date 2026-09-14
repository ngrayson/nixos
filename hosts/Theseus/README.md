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

## Display

`hypr/Theseus/monitors.conf` starts from the Framework 13 2880x1920 panel at scale 1.6 on `eDP-1`. On Theseus, run `hyprmon-cfg` and rebuild if the scale or connector name is wrong.

## Fingerprint

`services.fprintd.enable` is on for Theseus only. SDDM login stays password-only. After switch, enroll with `fprintd-enroll`, then confirm `fprintd-list`. sudo / polkit / lock should use the reader.

## Keyboard backlight

Quickshell's bar still talks to `chromeos::kbd_backlight` (Intel Framework path). On Theseus, check `brightnessctl -l` — if the EC device is different (`framework_laptop::kbd_backlight` or similar), say so and we will host-gate the QML device name. Panel brightness keys use `brightnessctl -c backlight`.

## Roblox (Sober)

`sober.nix` installs Roblox through [Sober](https://flathub.org/apps/org.vinegarhq.Sober), the VinegarHQ Linux client, which ships only as a Flatpak. The module imports `nix-flatpak` (flake input) so `org.vinegarhq.Sober` is declared in `services.flatpak.packages` rather than installed by hand; `flatpak-managed-install.service` performs the install at activation and **needs network** — an offline switch still succeeds, the app is just absent until `systemctl start flatpak-managed-install`. The Flatpak is refreshed weekly by `flatpak-managed-install.timer`; Sober updates Roblox itself on launch.

After switch:

```bash
systemctl status flatpak-managed-install   # inactive (dead), exit 0
flatpak list --app                          # org.vinegarhq.Sober
flatpak run org.vinegarhq.Sober             # first launch downloads Roblox
```

Sober's data and config live under `~/.var/app/org.vinegarhq.Sober/` (`config/sober/config.json` for renderer / fflag tuning). Theseus-only: `profiles/workstation.nix` is shared with Tawa and stays Flatpak-free.

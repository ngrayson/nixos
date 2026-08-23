# Theseus: Framework AMD AI 300

The flake imports `nixos-hardware.nixosModules.framework-amd-ai-300-series` for this host. The checked-in `hardware-configuration.nix` is deliberately a non-deployable placeholder.

## Bring in the installed machine

On Theseus, copy the installer-generated hardware file:

```bash
sudo cp /etc/nixos/hardware-configuration.nix \
  ~/.config/nixos/hosts/Theseus/hardware-configuration.nix
```

Before building, inspect it and confirm:

- `/` and `/boot` use Theseus's real UUIDs.
- The LUKS mapping matches `lsblk -f`.
- `swapDevices` names the partition created by “swap with hibernate”.
- No all-zero placeholder UUID remains.

Do not copy Tawa's hardware file or UUIDs.

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

Reboot only after reviewing the dry activation. After boot, test `systemctl hibernate` with nonessential applications closed. A normal boot remains the recovery path if resume fails.

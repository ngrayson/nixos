# Go3 — Surface Go 3 kiosk

Always-on wall kiosk: `cage` runs one fullscreen Chromium on
`https://home.wizt.org` as `wiz`, autologin, no desktop. Shape is
[`profiles/kiosk.nix`](../../profiles/kiosk.nix) (imports `common/base.nix`
only) plus the host modules here.

| | |
|---|---|
| Hardware | Surface **Go 3**, 8 GB RAM, 128 GB KIOXIA KBG40ZPZ128G NVMe |
| Wi-Fi / BT | Intel AX200/AX201 — `iwlwifi` + `btintel`, stock mainline |
| Touch | ELAN9038 I²C-HID (`hid_multitouch`) + stylus — **not IPTS** |
| Kernel | mainline `linuxPackages_latest`, see `host.nix` |
| stateVersion | `26.05` (first install) |

## Why not the linux-surface kernel

`microsoft-surface-common` is imported in [`flake.nix`](../../flake.nix), but
`host.nix` forces mainline over it. The patched kernel builds from source with
no binary cache, and this machine needs none of its patches: the Type Cover is
USB HID rather than the SAM aggregator, the touchscreen is I²C-HID (per the
nixos-hardware Surface README the **Go range is the exception that does not use
IPTS**), and both radios bind on stock drivers. Hearth does the same thing for
the same reason.

Do **not** use `nixos-hardware.nixosModules.microsoft-surface-go` — that module
explicitly targets the Go 1 and pulls in the ath10k/QCA6174 firmware path,
which is wrong for an Intel-radio Go 3. Do not set
`hardware.microsoft-surface.firmware.surface-go-ath10k.replace`; it is obsolete
and emits a warning.

## Deploy

Built on Tawa, activated over SSH — the Hearth model. Never run
`os-rebuild switch --host Go3` on Tawa; that switches Tawa.

```bash
os-rebuild build --host Go3     # on Tawa
go3-deploy switch               # build, copy, activate
```

### The kiosk comes back on its own

A switch used to leave the wall screen blank. Upstream's `services.cage`
module sets `restartIfChanged = false`, so activation tore `cage-tty1` down
and never started it again — and `getty@tty1` grabs tty1 the moment cage
stops, because the two units `Conflicts`. Nobody watches an appliance deploy,
so it stayed dead until someone SSHed in.

[`profiles/kiosk.nix`](../../profiles/kiosk.nix) fixes both halves:

- `restartIfChanged = lib.mkForce true` — the kiosk flickers on every switch
  and comes back, which beats a silent dead screen.
- `ExecStartPre = "+chvt 1"` — logind grants DRM access on `/dev/dri/*` only
  to seat0's **ActiveSession**, so cage exits about ten seconds after start
  whenever another VT is active. That is why a bare `systemctl start
  cage-tty1` from SSH was never enough and always needed a `sudo chvt 1`
  beside it. Doing the `chvt` inside the unit makes boot, deploy restart and
  manual start all active-VT-correct. **Do not remove it** — the ACL problem
  comes straight back.

`go3-deploy switch` now confirms the kiosk returned instead of printing a
reminder, and it runs that check even when the rebuild exits non-zero: the
switch that applied `--ssh=false` cut its own SSH session and exited 255 with
activation already complete, which is exactly when the check matters.

If it ever does stay down: `go3-deploy ssh -- sudo systemctl restart cage-tty1`.

## Installing NixOS on this hardware

`NEW-SYSTEM.md` covers the general flow. Two Surface-specific traps cost an
evening on 2026-08-31 and are worth reading before the next one:

**1. Firmware updates are a one-way door.** Surface UEFI and device firmware
ship only through Windows Update. Run it to completion *before* wiping, or the
machine is frozen on whatever it shipped with. Enter UEFI with **Volume-Up +
Power**; disable Secure Boot (this repo has no lanzaboote, so it stays off).

**2. Calamares may not set the ESP partition type.** The 26.05 graphical ISO
loads the *sfdisk* KPMcore backend, where ticking the `boot` flag does not
reliably write the EFI System Partition type GUID — it can come out as
`EBD0A0A2-…` (Microsoft basic data). `nixos-install` then runs to completion
and dies on the very last step:

```
File system "/dev/nvme0n1p1" has wrong type for an EFI System Partition (ESP).
Failed to install bootloader
```

Check before proceeding past the partitioning page: Calamares' *"system is EFI
but no EFI system partitions found"* warning must clear. Repair without
reinstalling:

```bash
sudo sfdisk --part-type /dev/nvme0n1 1 C12A7328-F81F-11D2-BA4B-00A0C93EC93B
sudo partprobe /dev/nvme0n1
sudo mount /dev/nvme0n1p2 /mnt && sudo mount /dev/nvme0n1p1 /mnt/boot
sudo nixos-install --root /mnt --no-root-password
```

**3. A failed bootloader step silently skips the password jobs.** When
Calamares aborts at `bootctl`, it logs `Skipping non-emergency job "Set
password for user wiz"`. Re-running `nixos-install` by hand fixes the
bootloader but has no password job, so the machine boots to a login prompt
where `wiz` exists with a locked password and every attempt fails. This repo
never sets `users.mutableUsers` (so it defaults `true`) and no profile declares
a `hashedPassword` for `wiz`, so the installer's `usermod` is the only thing
that sets it. Fix from the ISO:

```bash
sudo mount /dev/nvme0n1p2 /mnt
sudo nixos-enter --root /mnt -c 'passwd wiz'
```

## Out of scope here

Display blanking and wake-on-camera/input are a separate card. Do not add DPMS
or suspend logic to `host.nix`; the kiosk deliberately never S3-suspends.

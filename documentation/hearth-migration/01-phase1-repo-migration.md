# Phase 1: Repo migration + Hearth host scaffold

Goal: `~/.config/nixos` becomes a checkout of the flake repo with a new
`Hearth` host that builds. Do not `switch` until phase 2's profile exists
(phase 1 + 2 land as one first rebuild).

## 1. Switch the working tree to the flake repo

Histories are unrelated; the old tree is preserved on a branch (phase 0):

```bash
cd ~/.config/nixos
git add -A && git commit -m "final standalone Surface config"   # if not done
git branch legacy/surface-standalone
git remote add flake https://github.com/ngrayson/nixos.git
git fetch flake
git checkout -B main flake/main
git branch --set-upstream-to=flake/main main
```

Untracked local files (`nixos-switch.log`, `documentation/hearth-migration/`)
survive the checkout. Old tracked files (`configuration.nix`, `wizos-rebuild`,
LICENSE, README) are replaced by the flake tree but remain reachable via
`legacy/surface-standalone`.

## 2. Create `hosts/Hearth/`

### `hosts/Hearth/hardware-configuration.nix` (preserved, edited)

Recover the machine's generated file and strip the channel-style import:

```bash
mkdir -p hosts/Hearth
git show legacy/surface-standalone:hardware-configuration.nix \
  > hosts/Hearth/hardware-configuration.nix
```

Edit: delete the `<nixos-hardware/microsoft/surface/common>` import line (it
moves to `flake.nix` as a flake-input module). Keep everything else verbatim:
filesystem UUIDs, 16 GiB swapfile, `kvm-intel`, initrd modules, DHCP default,
`hardware.cpu.intel.updateMicrocode`.

### `hosts/Hearth/configuration.nix`

```nix
{...}: {
  imports = [
    ../../profiles/media-desktop.nix   # created in phase 2
    ./hardware-configuration.nix
    ./host.nix
    ./jellyfin.nix                     # created in phase 5
  ];
}
```

### `hosts/Hearth/host.nix`

Carries over the host-specific bits of the old `configuration.nix`:

```nix
{...}: {
  networking.hostName = "Hearth";

  # Patched linux-surface kernel (module wired in flake.nix).
  hardware.microsoft-surface.kernelVersion = "stable";

  zramSwap.enable = true;
  zramSwap.memoryPercent = 25;

  # First install of this machine was 24.05 — never bump.
  system.stateVersion = "24.05";
}
```

(Media-host lid/power policy is added in phase 5.)

## 3. Register the host in `flake.nix`

Additive entry next to Tawa/Theseus/Gcp:

```nix
Hearth = mkHost [
  nixos-hardware.nixosModules.microsoft-surface-common
  ./hosts/Hearth/configuration.nix
];
```

`nixos-hardware` is already a flake input; confirm the exact module attribute
name with `nix flake show github:NixOS/nixos-hardware 2>/dev/null | grep -i surface`
(expected: `microsoft-surface-common`; there are also `microsoft-surface-pro-intel`
variants — pick `common` to match the old channel import).

## 4. Verify

```bash
git add -A                             # flake ignores untracked files
nix flake check 2>/dev/null || true    # eval sanity
nix build .#nixosConfigurations.Hearth.config.system.build.toplevel --dry-run
# Parity guardrail: Tawa/Theseus/Gcp toplevels unchanged (see README)
```

Note the dry-run will reveal the surface kernel derivation. If the from-source
kernel build is unacceptable on this machine, either build remotely
(`nixos-rebuild build --flake .#Hearth` on Tawa, then `nix copy`) or defer the
nixos-hardware module (stock kernel) and revisit in phase 4 if touch input
misbehaves.

**Implemented:** `microsoft-surface-common` is imported in `flake.nix` (firmware,
IIO, `mem_sleep_default=deep`). `hosts/Hearth/host.nix` then
`lib.mkForce`s `boot.kernelPackages` to `pkgs.linuxPackages_latest` because
linux-surface 6.19.8 has no binary cache and this Ice Lake machine already
enumerates IPTS + the HID touchpad on mainline 6.18. Drop the `mkForce` to
build the patched kernel later (preferably on Tawa).

## Dropped intentionally (vs old standalone config)

- `services.openvpn.servers.zurich` (VPN not part of the lightweight role)
- Steam + `programs.steam` firewall openings
- CUPS printing (re-add in profile if the Surface actually prints)
- All heavy desktop packages (see phase 2 package list)
- oh-my-zsh setup (replaced by repo HM zsh)

## Rollback

Old generations stay in the systemd-boot menu. The old tree is on
`legacy/surface-standalone`; `git checkout legacy/surface-standalone` +
`sudo nixos-rebuild switch` (channel-based) restores the previous world.

# World of Warcraft on Linux (Tawa)

How WoW is meant to run on Tawa: Battle.net as a non-Steam game under Steam,
forced onto GE-Proton. **Tawa only** — Theseus and the other hosts get nothing
from this.

Provenance is labelled. **Measured** means observed on Tawa. **Community** means
taken from third-party guides (some SEO-style) and not yet reproduced here;
treat those as starting values to verify. Blizzard's own support pages were not
checked.

## What the repo provides

| Piece | Where | State |
| --- | --- | --- |
| Steam, GE-Proton, gamescope, mangohud | `programs.steam` in `profiles/workstation.nix` | Already enabled (shared with Theseus) |
| 32-bit graphics | set by the Steam module | `hardware.graphics.enable32Bit` evaluates `true` on Tawa (measured) |
| GPU | RX 6700 class (Navi 22) on RADV | Measured |
| GameMode + warmth hold | `hosts/Tawa/host.nix` | Already enabled; `gamemoderun` pauses hyprsunset while a game runs |
| NTSYNC | `boot.kernelModules` in `hosts/Tawa/host.nix` | Added by this change, Tawa only |

NTSYNC is Linux's kernel-native NT synchronisation primitive set. The kernel is
built with `CONFIG_NTSYNC=m` (measured), but the module is not autoloaded, so
`/dev/ntsync` did not exist before this change (measured). Proton only uses it
when `PROTON_USE_NTSYNC=1` is set *and* the device exists.

## Why Steam + GE-Proton

| Route | Verdict |
| --- | --- |
| **Steam non-Steam shortcut + GE-Proton** | Chosen. Runner is pinned by Nix (`proton-ge-bin`), nothing new to install, listed as supported on the [NixOS wiki](https://wiki.nixos.org/wiki/Battle.net). |
| Lutris + umu-launcher + GE-Proton | Works, but the prefix and runner are mutable state outside Nix and it adds three packages. The fallback if this route fails: add `lutris`, `umu-launcher`, `winetricks` to **Tawa only**, never to `profiles/workstation.nix`. |
| Bottles | Skipped. Community reports trouble using system Wine or Wine 10 runners on NixOS. |

## One-time install (manual)

Nobody can script this; the Battle.net login is interactive.

1. Download `Battle.net-Setup.exe` from Blizzard.
2. Steam > Games > Add a Non-Steam Game > browse to the installer.
3. Properties > Compatibility > force the compatibility tool to the GE-Proton
   that `proton-ge-bin` provides (GE-Proton11-1 at the time of writing).
4. Set the launch options (below), then run the shortcut. **Do not log in during
   the first installer run**; finish the install, then launch Battle.net again
   and log in.
5. Install WoW **outside the prefix**, e.g. `~/Games/WoW`. Then a broken prefix
   can be deleted and rebuilt without re-downloading the client.

## Launch options

```
PROTON_USE_NTSYNC=1 gamemoderun %command%
```

- `WINE_SIMULATE_WRITECOPY=1` — add **only** if Battle.net shows a blank login
  or the Agent keeps corrupting (community, also on the NixOS wiki).
- Do **not** set `PROTON_ENABLE_WAYLAND`. Run under XWayland; the native Wayland
  driver is reported to cause black screens (community).
- `mangohud` is available inside the Steam FHS, but Blizzard's ToS does not
  explicitly permit overlays. Leave it off unless you want it.

## In-game settings (community, verify)

In `_retail_/WTF/Config.wtf`:

```
SET gxApi "d3d11"
SET maxFPS "60"
SET maxFPSBk "30"
```

DX12 is reported as less stable under Proton and ray tracing does not work.
DXVK 2.x builds shaders asynchronously (GPL), so light stutter in the first
session is expected.

## Security posture

- **Wine/Proton is not a sandbox.** Battle.net and WoW run as `wiz` and can read
  all of `$HOME`, including `~/.ssh`, `~/.claude`, and browser profiles. Steam's
  container does not change that for a non-Steam game. An isolation wrapper
  (separate home, hiding those paths) is a separate follow-up, not built here.
- **Warden / bans.** Blizzard describes Linux as unsupported, not prohibited
  (community, unverified against blizzard.com). Reports say Warden targets
  injectors, memory editors and bots, not the compatibility layer. Run no
  third-party automation next to the game.
- **Account.** The login happens in an embedded browser inside Wine. Use the
  Battle.net authenticator and a password unique to Blizzard.
- **Network.** WoW and Battle.net are outbound only. No firewall change is made
  or needed.

## Stability and recovery (community)

- Patches break compatibility two to four times a year; fixes usually follow in
  one to two days. Keep the previous GE-Proton selectable in the Steam
  compatibility menu, and do not start progression on patch day.
- Blank Battle.net window: toggle Settings > General > Hardware Acceleration.
- Agent corruption: kill the Blizzard processes, delete
  `ProgramData/Battle.net/Agent` inside the prefix, log in again.
- Launcher broken after a Proton or system update: re-run `Battle.net-Setup.exe`
  inside the existing prefix; no need to delete the prefix or the game.
- Persistent stutter: confirm NTSYNC below, then check Battle.net CPU use.

## Verifying NTSYNC

After `os-rebuild switch` (the module loads at boot; `sudo modprobe ntsync`
skips the reboot):

```sh
lsmod | grep ntsync
ls -l /dev/ntsync
```

Both must succeed. If Proton cannot open the device as `wiz` — unverified; check
the node's mode first — add to `hosts/Tawa/host.nix`:

```nix
services.udev.extraRules = ''KERNEL=="ntsync", MODE="0660", TAG+="uaccess"'';
```

and note here which was needed.

## Sources

- [Battle.net, NixOS Wiki](https://wiki.nixos.org/wiki/Battle.net)
- [World of Warcraft on Linux: The Real 2026 Guide, sudowheel](https://sudowheel.com/wow-on-linux-march-2026.html)
- [Battle.net on Linux: What Actually Works in 2026, sudowheel](https://sudowheel.com/battlenet-linux.html)

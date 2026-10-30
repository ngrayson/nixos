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
`/dev/ntsync` did not exist before this change (measured). GE-Proton11-1's
`proton` script sets `WINENTSYNC=1` by default (opt out with
`PROTON_NO_NTSYNC=1`) and its `wineserver` carries the ntsync code (both
measured by reading the shipped package), so no launch variable is needed once
the device exists. `PROTON_USE_NTSYNC` from some community guides is not read by
this build. Whether a running game actually holds `/dev/ntsync` open is checked
under *Verifying NTSYNC*.

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
5. Retarget the shortcut: it still launches the installer. Properties > Target
   becomes `Battle.net.exe` inside the prefix:
   `~/.local/share/Steam/steamapps/compatdata/<appid>/pfx/drive_c/Program Files (x86)/Battle.net/Battle.net.exe`
   (find `<appid>` with `ls -t ~/.local/share/Steam/steamapps/compatdata | head -3`;
   on Tawa the Battle.net prefix is `3773699819`, measured). Re-running the
   installer each time also works.
6. Install WoW **outside the prefix**, e.g. `~/Games/WoW` (in Battle.net's
   install dialog that is `Z:\home\wiz\Games\WoW`; Wine's `Z:` is `/`). Then a
   broken prefix can be deleted and rebuilt without re-downloading the client.

## Launch options

```
gamemoderun %command%
```

NTSYNC needs no variable (see above).

- `WINE_SIMULATE_WRITECOPY=1` — add **only** if Battle.net shows a blank login
  or the Agent keeps corrupting (community, also on the NixOS wiki).
- Do **not** set `PROTON_ENABLE_WAYLAND`. Run under XWayland; the native Wayland
  driver is reported to cause black screens (community).
- `mangohud` is available inside the Steam FHS, but Blizzard's ToS does not
  explicitly permit overlays. Leave it off unless you want it.

## Window management (Hyprland)

The game only offers **Windowed** and **Windowed Fullscreen**. Measured on Tawa
in Windowed Fullscreen: class `steam_app_3773699819`, title "World of Warcraft",
tiled, `fullscreen: 1` (maximized, not 2), 2526x1374 (gaps and border included),
tiled next to a tiled "Battle.net" window. Hyprland and the game then fight over
size, and the cursor is not confined at the screen edge. Two rules in
`home/wayland/hyprland.nix` fix it: the game window is put into real fullscreen
when it maps (no border, rounding or shadow), and the Battle.net window floats.
A live `hyprctl keyword windowrule` test was run first; after it, Nick asked for
the rules to be written. A read-back of `fullscreen: 2` from `hyprctl` was not
captured, so check it after a switch:

```sh
hyprctl -j clients | jq '.[] | select(.class|test("steam_app_3773699819")) | {title,fullscreen,floating}'
```

The title rule is a prefix match (`^World of Warcraft.*`) because the Classic
client's exact title was not captured; tighten it if a capture shows it.

## In-game settings

`Config.wtf` is written on first quit, under
`~/Games/WoW/World of Warcraft/<product>/WTF/` where `<product>` is `_retail_`,
`_classic_` or `_classic_era_` depending on what you installed (measured on
Tawa: `_classic_` and `_classic_era_` exist, not retail). Keys are spelled with
a capital in the files Classic wrote (`GxApi`, `GxMaximize`).

Starting values from a community guide (verify):

```
SET gxApi "d3d11"
SET maxFPS "60"
SET maxFPSBk "30"
```

Measured: Classic wrote `GxApi "D3D12"` by default. DX12 is reported as less
stable under Proton and ray tracing does not work, so D3D11 is the suggested
value, but that choice is yours and nothing here sets it. DXVK 2.x builds shaders
asynchronously (GPL), so light stutter in the first session is expected.

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

Both must succeed. Measured on Tawa after the switch: the module loads and
`/dev/ntsync` is `crw-rw-rw- root root 10,260`, world-accessible, so `wiz` can
open it and no udev rule is needed. (If a future kernel tightens the mode, add
`services.udev.extraRules = ''KERNEL=="ntsync", MODE="0660", TAG+="uaccess"'';`
to `hosts/Tawa/host.nix`.) Whether Proton actually picks it up in a game has not
been checked.

## Sources

- [Battle.net, NixOS Wiki](https://wiki.nixos.org/wiki/Battle.net)
- [World of Warcraft on Linux: The Real 2026 Guide, sudowheel](https://sudowheel.com/wow-on-linux-march-2026.html)
- [Battle.net on Linux: What Actually Works in 2026, sudowheel](https://sudowheel.com/battlenet-linux.html)

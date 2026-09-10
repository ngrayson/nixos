# Pixel Composer on Linux (Tawa)

How Pixel Composer is launched here, why its windows behave the way they do
under Hyprland, and how to capture evidence for a bug card with `pxc-debug`.

Everything below was measured on Tawa, not inferred. Where a number is quoted
it came from `hyprctl`, `xwininfo` or `xprop` on this machine.

## The two launch paths

**AppImage (native Linux build) — the primary path.**
`desktop/applications/pixel-composer.desktop` runs `pxc-launch`, which resolves
the newest `~/bin/Pixel_Composer_*-x86_64.AppImage` (or `$PXC_APPIMAGE`) and
execs it through `appimage-run`. That runner is the `appimageRunWithCurl`
override in `common/appimage-run-curl.nix`, wired by `programs.appimage` in
`profiles/workstation.nix`; it runs the payload in a bwrap FHS environment with
both `DISPLAY=:1` and `WAYLAND_DISPLAY=wayland-1` set.

The runner binary links `libX11`/`libGL` directly — **no SDL, no Wayland**. It
is XWayland-only and there is no native-Wayland switch to flip. PC's log for
this path is `~/PixelComposer/log/log.txt`.

**Steam (Windows build under Proton) — secondary.**
Steam app 2299510, `beta` branch, mapped to `proton_experimental`. The depot
contains only `PixelComposer.exe` + `data.win` + DLLs — no Linux binary. Its
window carries a real `WM_CLASS` of `steam_app_2299510`, which is the only
reliable way to tell it apart from the AppImage.

`pxc-debug start steam --attach` collects against it without launching it.

> **History worth knowing.** The AppImage was believed broken for a long time.
> It was not — it was *invisible*. See the placement section below. Because it
> is a native build with no Wine layer between it and the compositor, it is the
> better surface for diagnosing window-management bugs.

## Why the AppImage window used to be invisible

The monitor layout, from `hyprctl -j monitors`:

| output | position | size | transform | occupies |
| --- | --- | --- | --- | --- |
| DP-3 | (0, 0) | 2560x1440 | 3 | x ∈ [0, 1440], y ∈ [0, 2560] |
| HDMI-A-1 | (1440, 544) | 2560x1440 | 0 | x ∈ [1440, 4000], y ∈ [544, 1984] |
| DP-1 | (4000, 0) | 2560x1440 | 1 | x ∈ [4000, 5440], y ∈ [0, 2560] |

DP-1 and DP-3 are rotated, so each occupies `height x width`, not
`width x height`. The desktop union is **x ∈ [0, 5440], y ∈ [0, 2560]** — not
6560 wide, as earlier notes had it.

XWayland does **not** share that layout. Hyprland packs the X11 screen
left-to-right at y=0 in monitor order, so `DISPLAY=:1 xrandr` reports DP-1 at
X11 0, DP-3 at 1440, HDMI-A-1 at 2880.

Pixel Composer centres itself on the **first X11 output** using GameMaker's
`display_get_width/height` — DP-1, portrait — and asks for X11 `(240, 453)`.
Hyprland then translates that request as
`coord - monitor.xwaylandPosition + monitor.position`, anchored on the
**window's own monitor** rather than the one whose X11 rect contains the point.
Anchored on whatever had focus:

```
(240,453) - DP-1_x11(2880,0) + HDMI-A-1_global(1440,544) = (-1200, 997)
```

Entirely left of x=0, so nothing ever appeared. The same formula reproduces the
Steam window at the same moment: X11 `(2882,42)` → `[1442, 586]`.

**The fix is an anchor, not a position.** `home/wayland/hyprland.nix` carries
`match:title ^Pixel Composer.*, float on, monitor DP-1`, which makes the same
request resolve to `(240,453) - (0,0) + (4000,0) = (4240, 453)` — where the app
meant to put itself.

`center on` was tried first and **does not work**: the app issues its own
ConfigureRequest after the window maps, which overrides any static placement
rule. `move` loses the same race. Do not re-try placement rules here without
re-testing that ordering.

## Popups are separate X11 toplevels

PC's file dialog, splash and error dialogs are **not** in-surface overlays.
They are separate transient X11 toplevels that carry the *same title* as the
main window, with `WM_TRANSIENT_FOR` pointing at it and fixed `WM_NORMAL_HINTS`
(`min = max`). They have no `WM_CLASS` and no `_NET_WM_WINDOW_TYPE`.

Two consequences:

1. Every `^Pixel Composer.*` window rule hits the popups as well as the main
   window. There is no class to discriminate on.
2. **`hyprctl clients` lists only mapped windows.** A popup that maps and
   unmaps quickly — the reported "flicker" — never appears there at all.
   `xwininfo -root -tree` sees it; `hyprctl` does not. Never conclude a popup
   did not exist from `hyprctl clients` alone.

Hyprland auto-floats such windows (transient + fixed size hints) and keeps
transients with their parent in z-order.

## Other Hyprland interactions in play

`general:resize_on_border` is **global** and deliberately so. A press within
`border_size + extend_border_grab_area` (15) of the window edge, or inside a
rounded corner, is taken by the compositor for a resize before it reaches the
app. PC draws its own resize handles inside its edges and corners, so the two
overlap. `decoration:rounding` is 25.

⚠️ **Do not Super+drag a Pixel Composer window** until you have confirmed the
running compositor carries the `#15833` backport (check the store path of
`/proc/<pid>/exe`, not `hyprctl version` — the patch does not move the tag).
On an unpatched 0.55.4 a rejected drag segfaults the compositor and ends the
session.

## Capturing evidence for a card

```
pxc-debug start appimage          # or: start steam --attach
  ... reproduce the bug ...
pxc-debug mark file dialog vanished
pxc-debug stop
pxc-debug report                  # paste this into the card
```

`start` writes a run directory under `$XDG_RUNTIME_DIR/pxc-debug/<timestamp>/`
containing:

| file | what it holds |
| --- | --- |
| `meta.txt` | launch path, PC build, Hyprland version, monitors, the relevant options, submap |
| `hypr-events.log` | Hyprland's event socket, timestamped, filtered to window/submap events |
| `x11-tree.log` | the X11 tree plus per-window map state and hints, **appended only when it changes** |
| `clients.log` | `hyprctl clients` for PC windows, same diff-on-change cadence |
| `pc-log.txt` | PC's own log |
| `mark-<n>/` | full unfiltered snapshots taken at each `mark` |

The logs are diff-on-change rather than every sample: a 250 ms poll that logged
unconditionally would bury the one transition that matters.

`mark` is the collaborative hook — hit the bug, run it immediately, and the
timestamp lets `report` slice ±5 s of every log around that moment.

`stop` kills the collectors and **leaves Pixel Composer running**.

`report` rewrites `$HOME` to `~` and drops any line mentioning `Documents`, so
its output is safe to paste onto a card. Never paste raw PC or Steam logs —
they contain project paths.

## Open symptom cards

Each is a separate card; none is fixed by the harness.

| symptom | card |
| --- | --- |
| PC's own resize handles lose to `resize_on_border` | `pixel-composer-its-own-resize-handles-lose-to-hyprland-s-res` |
| popups (file dialog, splash) end up hidden | `pixel-composer-popup-windows-file-dialog-splash-end-up-hidde` |
| new-node modal keeps the mouse, no Esc | `pixel-composer-new-node-modal-keeps-the-mouse-and-no-longer` |
| error dialogs render as bordered windows and flicker | `pixel-composer-error-dialogs-render-as-bordered-hyprland-win` |

If the harness turns up a further distinct symptom, file it as its own card
tagged `pixel-composer` rather than folding it into an existing one.

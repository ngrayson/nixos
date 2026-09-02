## What this is
The Hyprland session bar and lock live in `quickshell/` (`shell.qml`, `PowerMenu.qml`, `LockSurface.qml`). Home Manager starts one `quickshell -d -p` from `home/wayland/hyprland.nix`. IPC goes through `qs-quickshell-ipc` (`home/hypr/scripts.nix`), which prefixes `ipc -p <live config> -n` so calls hit the running bar.

## Locking the screen is a user-confirmed action
**Ask before you lock anything.** This applies to both the real session lock (`qs-quickshell-ipc call lock activate`) and the non-locking test overlay (`qs-quickshell-ipc call lock preview`). Nick is usually sitting at this machine, and locking is not a scoped, undoable edit — it seizes every monitor. `lock activate` also runs `hypr-dpms-side-off`, which DPMS-blanks every output except one, so it takes over the whole desk rather than a window.

**Clear your own lock tests.** Never leave a preview or a lock on screen for someone else to dismiss:

- `qs-quickshell-ipc call lock cancelPreview` — clears the preview overlay. This is the *only* way out of a stuck preview; there is no `deactivate` for a real lock, by design.
- `hyprctl dispatch dpms on` — re-lights every monitor `blankSideMonitors()` turned off.
- Confirm you are clean: `hyprctl layers | grep qs-lock-preview` returns nothing, and `hyprctl monitors -j | jq '.[] | select(.dpmsStatus == false)'` returns nothing.

This matters more than it sounds. Both the lock and the preview draw their password box and wire their Esc handler on a single output chosen by `centerOutputScreen()` geometry, so from any other monitor there is no visible way out at all. On 2026-09-02 that stranded a Tawa session mid-task. Three cards are open against the underlying bug; until they land, assume a lock you start is a lock someone may not be able to end.

Before locking on a remote or headless-ish host, have a second way in (an SSH session already open) — a mistake here costs a TTY.

The same caution applies to anything else that commandeers the live session rather than staying inside the repo: moving the mouse cursor, taking screenshots, restarting the bar. Prefer verification that does not take over the desktop, and say what you are about to do first.

## After you change QML or binds
1. Do **not** spawn a second `quickshell`. The old process keeps the layer-shell seats and the new one will fight it.
2. End the old bar, then start one from the live config: `qs-quickshell-reload` (or the bar reload pill). After an `os-rebuild switch` that changed `hyprland.nix` binds, also `hyprctl reload` (or log out) so `bindl` is picked up.
3. Processes started **from** Quickshell (or that call `qs-quickshell-ipc`) keep working against the same live path. If you pointed a terminal at `~/.config/quickshell` while HM is using the store/live tree, `ipc -p` will miss the running instance — use `qs-quickshell-ipc`.

## Power / lock IPC
- `qs-quickshell-ipc call lock activate` — session lock (`Super+L`). **Confirm with the user first** (see above).
- `qs-quickshell-ipc call lock preview` / `cancelPreview` — non-locking test overlay. **Confirm first, and always cancel it when done.**
- `qs-quickshell-ipc call power toggle` — short `XF86PowerOff` (no-op while locked; lock surface has its own power row).
- Methods need an explicit `: void` return or Quickshell will not register them.
- `cancelPreview` is a `void` IPC and returns 0 whether or not a preview was open — its exit code is not evidence that one existed.

## Do not
- Edit `hosts/Theseus/hibernate.nix` or logind lid / `HandlePowerKeyLongPress` for bar work.
- `sudo` yourself to activate; give the user `os-rebuild switch`.
- Lock the screen, or open the lock preview, without asking — and never walk away from one you started.

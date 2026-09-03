## What this is
The Hyprland session bar and lock live in `quickshell/` (`shell.qml`, `PowerMenu.qml`, `LockSurface.qml`). Home Manager starts one `quickshell -d -p` from `home/wayland/hyprland.nix`. IPC goes through `qs-quickshell-ipc` (`home/hypr/scripts.nix`), which prefixes `ipc -p <live config> -n` so calls hit the running bar.

## Locking the screen is a user-confirmed action
**Ask before you lock anything.** This applies to both the real session lock (`qs-quickshell-ipc call lock activate`) and the non-locking test overlay (`qs-quickshell-ipc call lock preview`). Nick is usually sitting at this machine, and locking is not a scoped, undoable edit — it seizes every monitor. `lock activate` also runs `hypr-dpms-side-off`, which DPMS-blanks every output except one, so it takes over the whole desk rather than a window.

**Clear your own lock tests.** Never leave a preview or a lock on screen for someone else to dismiss:

- `qs-quickshell-ipc call lock cancelPreview` — clears the preview overlay from anywhere, including over SSH. Reach for this first if a preview is stuck. There is no `deactivate` for a real lock, by design.
- `hyprctl dispatch dpms on` — re-lights every monitor `blankSideMonitors()` turned off.
- Confirm you are clean: `hyprctl layers | grep qs-lock-preview` returns nothing, and `hyprctl monitors -j | jq '.[] | select(.dpmsStatus == false)'` returns nothing.

This matters more than it sounds. Both the lock and the preview used to draw their password box and wire their Esc handler on a single output chosen by `centerOutputScreen()` geometry, so from any other monitor there was no visible way out at all. On 2026-09-02 that stranded a Tawa session mid-task.

Most of that is now fixed. The real lock draws its prompt on **every** output (PR #166), and the preview accepts Esc on every output and clears itself after two minutes. Two things are still worth knowing:

- **Esc is not a guarantee, the timeout is.** A layer-shell surface only receives keys once the compositor has given it focus, so on an output the user never clicked, Esc may not arrive. The preview's two-minute self-clear is the unconditional escape; `cancelPreview` is the immediate one.
- **The real lock has neither**, deliberately. It holds an `ext-session-lock`, so no keypress and no timer dismisses it — only the correct password. Assume a lock you start is a lock only the password ends.

Before locking on a remote or headless-ish host, have a second way in (an SSH session already open) — a mistake here costs a TTY.

The same caution applies to anything else that commandeers the live session rather than staying inside the repo: moving the mouse cursor, taking screenshots, restarting the bar. Prefer verification that does not take over the desktop, and say what you are about to do first.

## After you change QML or binds
1. Do **not** spawn a second `quickshell`. The old process keeps the layer-shell seats and the new one will fight it.
2. End the old bar, then start one from the live config: `qs-quickshell-reload` (or the bar reload pill). After an `os-rebuild switch` that changed `hyprland.nix` binds, also `hyprctl reload` (or log out) so `bindl` is picked up.
3. Processes started **from** Quickshell (or that call `qs-quickshell-ipc`) keep working against the same live path. If you pointed a terminal at `~/.config/quickshell` while HM is using the store/live tree, `ipc -p` will miss the running instance — use `qs-quickshell-ipc`.

## Seeing what the bar is actually doing
The running bar throws its output away. Both `stdout` and `stderr` symlink to `/dev/null` (`ls -l /proc/<pid>/fd/1`), and it is started as a bare `exec-once` from `home/wayland/hyprland.nix` rather than as a systemd user unit, so `journalctl --user` has nothing either. A terminal will never show you a QML error. This is the single most common way to waste an hour here: the bar comes back after a reload, so the change looks fine, and a broken binding sits there silently.

Quickshell keeps its own log, and the `log` subcommand reads it:

```
$ quickshell -p ~/.config/nixos/quickshell log
  INFO: Launching config: "/home/wiz/.config/nixos/quickshell/shell.qml"
  INFO: Saving logs to "/run/user/1000/quickshell/by-id/hktq8f6qkt/log.qslog"
  WARN: QSettings::value: Empty key passed
  INFO: Configuration Loaded
  WARN: Unable to determine system time zone: please check your system configuration.
```

`Configuration Loaded` with no `ERROR` lines is what tells you a reload actually worked. A `qs-quickshell-reload` exiting 0 proves nothing on its own — it only means the IPC request was delivered.

Useful flags (`quickshell log --help`): `-f`/`--follow` tails live, `-t N`/`--tail N` prints the last N lines, `-r`/`--rules` filters with `QT_LOGGING_RULES` syntax, and `-i`/`--id` or `--pid` picks a specific instance.

`quickshell list --all` shows every running instance with its PID, config path and uptime — the fastest way to confirm exactly one bar is up and which tree it was launched from:

```
$ quickshell list --all
Instance hktq8f6qkt:
  Process ID: 1251377
  Shell ID: ff5bc49a9125268257104c5dea3d1149
  Config path: /home/wiz/.config/nixos/quickshell/shell.qml
  Display connection: wayland/wayland-1
  Launch time: 2026-09-02 00:06:44 (running for 0 hours, 6 minutes, 1 seconds)
```

**Pass `-p`, or these lie to you.** `log` and `list` resolve the same way `ipc` does — bare, they look at `~/.config/quickshell/shell.qml`, the Home Manager fallback copy, and report:

```
$ quickshell log
[READER] No running instances for "/home/wiz/.config/quickshell/shell.qml"

$ quickshell list
No running instances for "/home/wiz/.config/quickshell/shell.qml"
Use --all to list all instances.
```

That reads as "the bar is dead". It is not — it is running from `~/.config/nixos/quickshell`, on a path you did not ask about. This is exactly the misresolution `qs-quickshell-ipc` exists to paper over; there is no equivalent wrapper for `log` yet, so pass `-p ~/.config/nixos/quickshell` yourself (or use `list --all`, which ignores the config path entirely).

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

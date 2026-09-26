# Hyprland's post-crash safe-mode relaunch

Decided 2026-09-21 (card `start-hyprland-s-post-crash-safe-mode-relaunch-comes-up-with`):
**the relaunch stays.** This page records what it does, what looks broken but
is not, and the one button not to press.

## What happens after a crash

SDDM starts the session through Hyprland's own `start-hyprland` launcher
(`share/wayland-sessions/hyprland.desktop`, `programs.hyprland` in
`profiles/workstation.nix`). When Hyprland exits uncleanly the launcher
relaunches it with `--safe-mode`, without a retry limit. In safe mode the
compositor does **not** read `~/.config/hypr/hyprland.conf`; it substitutes a
generated Lua recovery config (`<instance>/recoverycfg.lua`, the bundled
`example/hyprland.lua`) and shows a dialog with *Load config*, *Open crash
report dir* and *Understood*.

Source (Hyprland 0.55.4): `src/config/supplementary/jeremy/Jeremy.cpp:26-28`
swaps the config path when `m_safeMode` is set;
`src/config/ConfigManager.cpp:43-47` picks the Lua manager for the `.lua`
path.

## What looks broken and is not

- **Monitors side by side, not the configured layout.** The recovery config's
  monitor rule is `position = "auto"`, which lays outputs out left to right.
  That is the recovery config working as designed, not the real config being
  ignored.
- **`hyprctl configerrors` says `hyprland.conf:1: syntax error near '-'`.**
  This appears only after pressing *Load config* (below). The file is fine —
  the same binary parses it cleanly in a fresh login.

## The trap: do not press "Load config"

*Load config* clears safe mode and calls `reload()` on the config manager
that is already running — the **Lua** one (`src/Compositor.cpp:2683-2686`;
`initConfigManager()` early-returns once a manager exists,
`ConfigManager.cpp:16-17`). The Lua parser is then handed the hyprlang
`.conf`, tokenises `exec-once` as `exec - once`, and reports the syntax error
above. Nothing recovers from that inside the session.

**Instead: log out and log back in.** A fresh SDDM login runs
`start-hyprland` without `--safe-mode`, the hyprlang manager is selected, and
the real config and monitor layout come back. Reported upstream on card
`report-upstream-hyprland-s-safe-mode-load-config-hands-the-l`.

## Why the relaunch is kept

Disabling it (a custom `wayland-sessions/*.desktop` pointing SDDM at `Hyprland`
directly) would drop you to the SDDM login after a crash instead of a recovery
session, lose the watchdog, and make Hyprland print a no-watchdog notice at
every start. Landing on a generic layout until re-login is the cheaper
failure. Revisit only if the upstream fix changes the trade.

## If you need evidence from a relaunched instance

Before killing it, from the same user session:

```sh
pid=$(pgrep -x .Hyprland-wrapp | head -1)
tr '\0' '\n' < /proc/$pid/cmdline          # expect --safe-mode
sig=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1)
cp $XDG_RUNTIME_DIR/hypr/$sig/hyprland.log ~/.cache/hyprland/relaunch-$sig.log
grep -n '\[cfg\]' ~/.cache/hyprland/relaunch-$sig.log   # "Config is lua, loading lua mgr"
```

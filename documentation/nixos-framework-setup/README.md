# NixOS docs (Tawa / `~/.config/nixos`)

This directory contains the active rebuild helper plus archived planning material from the original Framework migration.

## Use on Tawa

- **Rebuild / migrate:** **[`MIGRATION.md`](../../MIGRATION.md)** (path ownership, migration log).
- **New machine / clone:** **[`NEW-SYSTEM.md`](../../NEW-SYSTEM.md)**.
- **Home Manager implementation:** **[`home/default.nix`](../../home/default.nix)** and the rest of **[`home/`](../../home/)**.

## Flake-aware rebuild helper

- **[`os-rebuild.sh`](./os-rebuild.sh)** — guided `nixos-rebuild` wrapper. The zsh alias **`os-rebuild`** points here.
- Targets the current hostname by default, or a named flake output with `--host`.
- Supports `build`, `dry-activate`, `test`, `switch`, and `boot`.
- Formats and checks the flake before rebuilding, shows the Git diff summary, and logs rebuild output under `~/.cache/os-rebuild`.

Examples:

```bash
os-rebuild build --host Tawa
os-rebuild dry-activate --host Tawa
os-rebuild boot --host Theseus
```

Use `--yes` only for noninteractive validation. `--commit` is opt-in and still asks before committing all repository changes.

## Archived Framework / Theseus roadmap

Historical **LOCKED**, audit, phased checklists, Framework-specific notes, and **`snippets/`** live under **[`archive/`](./archive/)**. Links inside those files were adjusted for the extra directory level; they are kept for reference only.

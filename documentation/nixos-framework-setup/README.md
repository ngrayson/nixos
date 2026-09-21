# NixOS docs (Tawa / `~/.config/nixos`)

This directory contains the active rebuild helper plus archived planning material from the original Framework migration.

## Use on Tawa

- **Rebuild / migrate:** **[`MIGRATION.md`](../../MIGRATION.md)** (path ownership, migration log).
- **New machine / clone:** **[`NEW-SYSTEM.md`](../../NEW-SYSTEM.md)**.
- **Home Manager implementation:** **[`home/default.nix`](../../home/default.nix)** and the rest of **[`home/`](../../home/)**.

## Flake-aware rebuild helper

- **[`os-rebuild.sh`](./os-rebuild.sh)** — guided `nixos-rebuild` wrapper. The zsh alias **`os-rebuild`** points here.
- Targets the current hostname by default, or a named flake output with `--host`.
- Supports `explain`, `check`, `build`, `dry-activate`, `test`, `switch`, and `boot`.
- Uses the Git-backed flake and validates every output before rebuilding.
- Explains whether changes affect flake inputs, shared base modules, Home Manager, the selected host, hardware, another host, or only documentation/tooling.
- Shows `git status` plus the full `git diff HEAD` (stat and patch) before check/build/activation. Tracked dirty files are included in the rebuild. After success it *offers* to commit them: interactively it prompts (default yes), `--yes` commits without prompting, and `--no-commit` never commits. **With no terminal attached it does not commit at all** — it leaves the tree dirty and says to pass `--commit`, which is the only way to commit non-interactively. That case is checked before `--yes` on purpose: `--yes` skips the *rebuild* confirmation and is not taken as an answer to the commit question, because a dirty tree is recoverable and an unwanted commit spanning unrelated work is not.
- Refuses to activate a different host accidentally, refuses placeholder hardware UUIDs, and prompts to stage untracked configuration inputs (a Git flake cannot see them otherwise). `--yes` stages those files without asking.
- Logs rebuild output under `~/.cache/os-rebuild`.

Examples:

```bash
os-rebuild explain --host Tawa
os-rebuild check --host Tawa
os-rebuild build --host Tawa
os-rebuild dry-activate --host Tawa
os-rebuild switch --host Tawa
os-rebuild boot --host Theseus
```

## Understanding configuration scope

Run `os-rebuild explain` at any time; it does not evaluate or build. The same report appears before every check or rebuild:

- **FLAKE / INPUTS:** `flake.nix` or `flake.lock`; may change dependencies or every host output.
- **SHARED BASE:** `common/` and `profiles/`; may affect multiple hosts.
- **HOME / DESKTOP:** Home Manager and workstation assets.
- **HARDWARE:** generated disk, filesystem, initrd, and device configuration for the selected host. Prefer `build` → `dry-activate` → `boot`.
- **HOST:** settings under `hosts/<selected-host>/`.
- **OTHER HOST:** visible for awareness but normally irrelevant to the selected output.
- **DOCS / TOOLING:** normally no system-closure effect.

The helper deliberately does not use a broad `path:` flake URI: that could copy Git-ignored secrets into the Nix store. Untracked configuration files are listed; before a check or rebuild you are asked to stage them so the flake can see them.

## Guided editing

`--edit` presents a menu for shared base, flake, host, hardware, or Home Manager files. A scope can also be selected directly:

```bash
os-rebuild --edit=base explain
os-rebuild --edit=flake check
os-rebuild --edit=hardware --host Theseus build
```

Formatting is opt-in with `--format`; validation no longer mutates files automatically. Activation actions default to **No** at the confirmation prompt. `--yes` is intended for deliberate noninteractive use. After a successful rebuild the script offers to commit dirty changes — prompting interactively, skipping with `--no-commit`, and committing non-interactively only with `--commit`. With no terminal attached it leaves the tree dirty rather than committing on your behalf.

## Archived Framework / Theseus roadmap

Historical **LOCKED**, audit, phased checklists, Framework-specific notes, and **`snippets/`** live under **[`archive/`](./archive/)**. Links inside those files were adjusted for the extra directory level; they are kept for reference only.

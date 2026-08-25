# Agent rules

This file is the Claude/Conveyor counterpart to `.cursor/rules/agent-workflow.mdc`. Follow both.

Canonical tree: `~/.config/nixos` (flake `github:ngrayson/nixos`). Hosts: **Tawa** (desktop), **Theseus** (Framework laptop), **Hearth** (Surface media host), **Gcp**.

- **`main` is stable, `dev` is unstable.** New hosts stay on `main`. Daily work happens on `dev` until you promote. Never `git switch` the user's checkout unless they ask.
- `os-rebuild` uses the **active checkout** and must tell the user which branch/lane they are on. It does not pick a branch. `hearth-deploy` **builds** the checkout; **switch/boot** default to `origin/deploy/hearth` unless `--from-checkout`.
- Never run `sudo` yourself. Give the user the command plus a check (`readlink /run/current-system`, or `qs-nixos-status`).
- Activate **this machine** with `os-rebuild switch`. **Do not** `os-rebuild switch --host Hearth` on Tawa — that activates Tawa as if it were Hearth.
- **Do not** write Tawa's `applied.json` after a Hearth deploy.
- **Hearth** is built on the builder (usually Tawa) and activated with `hearth-deploy` (`scripts/hearth-deploy.sh`). switch/boot use `origin/deploy/hearth` unless `--from-checkout`. Do not routine-switch Hearth on-box. Exception: the first on-box Hearth switch after `hosts/Hearth/remote-access.nix` trust/sudo changes.
- Git flake: **untracked files are invisible**. `git add` anything Nix must see.
- Commit **after** a successful rebuild, on the current branch. One logical change per switch.
- Hardware / kernel / disk / Hearth headless flip: `boot`, then reboot. `test` is not a rollback.
- Do not `nix flake update` unless asked. Do not copy hardware UUIDs, LUKS mappings, or swap devices between hosts.

Tawa/Theseus import `profiles/workstation.nix`. Do not grow `common/base.nix` with display managers, gaming, VPN, or Home Manager. Hearth uses `profiles/media-desktop.nix`. Gcp uses `profiles/server.nix` and has no `hardware-configuration.nix`.

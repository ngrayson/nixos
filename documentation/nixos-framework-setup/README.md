# NixOS on Framework — setup roadmap

**Plan status:** **LOCKED** (2026-04-05) — authoritative snapshot: [LOCKED.md](./LOCKED.md)

**Continue implementation:** [06-implementation-checklist.md](./06-implementation-checklist.md) — **Next:** small **optional** items in [Quick reference](./06-implementation-checklist.md#quick-reference) (`outside`, Stylix, extra suspend metrics, etc.). **Phase D** (Home Manager user config) is **done** on the live `~/.config/nixos` repo under [`./home/`](../../home/) — see [06 — § D](./06-implementation-checklist.md#d--home-manager-phase-d-migration-deferred).

**Where we are (2026-04):** **Bootstrap (A)**, **base system (B)**, **session (C)**, **Home Manager (D)** on the live machine, and **rice (E)** are **complete** for Theseus; see [06 — Current status](./06-implementation-checklist.md#current-status-rolling). **Outstanding:** small **optional** items in [06 — Quick reference](./06-implementation-checklist.md#quick-reference) (e.g. `outside` CLI, extra suspend metrics, **Stylix**).

This folder is your **organized todo** for turning a fresh NixOS install on a Framework laptop into a capable, comfortable, and good-looking daily driver.

## How this relates to the Stellarium wrapper repo

**Stellarium** (repository root) is the **project wrapper** — templates, `scripts/` for scaffolding, `registry/`, and so on. The Stellarium root [`.gitignore`](../../.gitignore) ignores the whole **`projects/`** tree, so this roadmap is **not** on Stellarium’s `main` history unless you force-add it. It is also **not** a scaffolded codebase from **`new-project.sh`** and does **not** go through **`add-to-registry`** like CLI/web apps under `projects/<type>/`.

**Authoritative git for the live machine:** your **NixOS configuration** in its **own repository** (often `~/.config/nixos/`). **Vendor a full copy** of this directory into that repo (e.g. `documentation/nixos-framework-setup/`) if you want the roadmap versioned and pushed with `nixos-rebuild` config; **do not rely on symlinks** if you need portable clones. A second copy may stay here under Stellarium for editing — **sync manually** when you want them to match.

The **`os-rebuild`** helper: same folder as this README — [`os-rebuild.sh`](./os-rebuild.sh) (or install from Stellarium’s [quickstart](../../documentation/quickstart.md) if a root `scripts/os-rebuild.sh` exists). It uses **`NIXOS_CONFIG`** / **`NIXOS_DIR`** (defaults under `~/.config/nixos`). **Connect and push** the nixos config remote so backups and `git` features refer to a real upstream — independent of Stellarium’s `origin`. See [Phase 1 — config repo git](./01-baseline-nix-packages.md#config-repo-git-nixos_dir).

**Start here for execution order, value vs complexity, risks, and decisions:** [00-audit-priorities-and-risks.md](./00-audit-priorities-and-risks.md)

## How to use these files

- Work **in order** (baseline → function → Home Manager → rice), or jump ahead only when a phase no longer blocks you.
- **Check off** items as you go (`[ ]` → `[x]`).
- When something fails, note the **error and what you tried** at the bottom of that phase file (short bullets).

## Phases

The numbered files are the **content** of each stage; [00-audit-priorities-and-risks.md](./00-audit-priorities-and-risks.md) recommends an **internal order** (bootstrap → base system → WM/terminal → Home Manager → rice) so Phase 2 does not turn into a single overloaded step.

| Phase | File | Goal |
|--------|------|------|
| 1 | [01-baseline-nix-packages.md](./01-baseline-nix-packages.md) | Reliable ways to **find**, **evaluate**, and **install** NixOS packages (CLI + mental model). |
| 2 | [02-functional-improvements.md](./02-functional-improvements.md) | **Kitty** + **zsh** (essential plugins); **tiling WM** + **muscle-memory hotkeys**; other day-to-day software; Framework-friendly bits. |
| 3 | [03-home-manager.md](./03-home-manager.md) | **Home Manager** + **chezmoi** ([debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main)): user config without fighting two managers. |
| 4 | [04-ricing.md](./04-ricing.md) | **Aesthetic overhaul**: theme, fonts, bar, launcher, wallpaper, consistency. |
| — | [06-implementation-checklist.md](./06-implementation-checklist.md) | **Do this next** — A→E steps after LOCKED (bootstrap → base → session → HM → rice). |

## Reference

| File | Purpose |
|------|---------|
| [LOCKED.md](./LOCKED.md) | **Frozen decision snapshot** — read this to see what was agreed without rereading the full audit |
| [00-audit-priorities-and-risks.md](./00-audit-priorities-and-risks.md) | **Audit**, value×complexity, refined phase order, **risks**, Q1–Q10 discussion |
| [05-previous-nixos-config-extract.md](./05-previous-nixos-config-extract.md) | **Portable settings and packages** from your prior NixOS machine (vs this Framework + tiling plan). |

## Quick links (official)

- [NixOS Manual — Package Management](https://nixos.org/manual/nixos/stable/#sec-package-management)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Framework + Linux](https://frame.work/linux) (hardware notes and community)

## Baseline tooling (community)

Phase 1 discusses these; use any one or combine:

- [nix-community/nixos-cli](https://github.com/nix-community/nixos-cli) — NixOS-oriented CLI helpers
- [peterldowns/nix-search-cli](https://github.com/peterldowns/nix-search-cli) — search UX on top of Nix

## Existing dotfiles (chezmoi)

Templates today target **Debian** and **Omarchy** (a Linux distribution); reuse as a **starting point** for shell aliases, Kitty, and other config — see Phase 3 for how this meets Home Manager on NixOS.

- [ngrayson/debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main) (main branch)

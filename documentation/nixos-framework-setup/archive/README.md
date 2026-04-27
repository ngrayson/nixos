# Archived: NixOS on Framework — setup roadmap

**Why archived:** These files tracked a **Framework laptop (Theseus)** install: phased checklist, WM/hotkey tables, Framework display notes, dotfiles migration narrative, and the **2026-04-05 LOCKED** snapshot. **Tawa** (this repo’s default desktop) does not use that workflow day-to-day.

**Live config** for this machine: repo root **[`MIGRATION.md`](../../../MIGRATION.md)**, **[`home/`](../../../home/)**, **[`common/system.nix`](../../../common/system.nix)**.

| File | Notes |
|------|--------|
| [`LOCKED.md`](./LOCKED.md) | Original decision table + rolling notes |
| [`00-audit-priorities-and-risks.md`](./00-audit-priorities-and-risks.md) through [`06-implementation-checklist.md`](./06-implementation-checklist.md) | Phases A–E |
| [`08-dotfiles-migration-plan.md`](./08-dotfiles-migration-plan.md) | Chezmoi / HM narrative |
| [`nixos-framework-project.md`](./nixos-framework-project.md) | Stellarium `projects/` layout (meta) |
| [`snippets/`](./snippets/) | e.g. `zsh-ns-alias.nix` fragment |

**`os-rebuild.sh`** was **not** archived; it remains **[`../os-rebuild.sh`](../os-rebuild.sh)** so existing aliases keep working.

# WizOs

NixOS flake for four named hosts. Canonical tree: `~/.config/nixos` (`github:ngrayson/nixos`).

**`main` is stable. `dev` is unstable.** Daily work and agent PRs live on `dev`. Lane rules: [BRANCHING.md](./BRANCHING.md).

| Host | Role | How it is activated |
|------|------|---------------------|
| **Tawa** | Desktop, Hearth builder | `os-rebuild switch` **on Tawa** |
| **Theseus** | Framework laptop | `os-rebuild switch` **on Theseus** |
| **Hearth** | Surface Laptop 3 media host | `hearth-deploy` **from Tawa** (or Theseus) |
| **Gcp** | Minimal GCE image | `scripts/gcp/` (build / upload / create) |

Flake outputs: `nixosConfigurations.{Tawa,Theseus,Hearth,Gcp}`.

## Start here

- New machine: [NEW-SYSTEM.md](./NEW-SYSTEM.md) (includes sops-nix / Bitwarden age-key bootstrap)
- Agent rules: [AGENTS.md](./AGENTS.md)
- Hearth source of truth: [hosts/Hearth/plan.md](./hosts/Hearth/plan.md)
- Cursor CLI: [CURSOR_SETUP.md](./CURSOR_SETUP.md)
- History / path table: [MIGRATION.md](./MIGRATION.md)

`legacy/surface-standalone` is listed in BRANCHING.md as the pre-flake Surface rollback. It is **not** on `origin` today — do not invent the branch.

`nix flake check` evaluates all four hostnames (not full toplevel — too heavy for 8 GB codespaces). Conveyor codespaces still need a **valid machine type in WizOs Project Settings** (launch already failed HTTP 400); they must never `nixos-rebuild`.

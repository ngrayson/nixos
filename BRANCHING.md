# Branch layout

| Branch | Purpose |
|--------|---------|
| **`main`** | **Stable.** New hosts start here. Promoted, reviewed work only. Conveyor releases and generated-file deliveries land here. Each machine builds `nixosConfigurations.<hostname>`. |
| **`dev`** | **Unstable.** Daily host work and Conveyor agent PRs. A machine stays on `dev` until you decide to promote it back to `main`. |
| **`legacy/previous-machine`** | Snapshot of **GitHub `main` before 2026-04** (prior NixOS install history). |
| **`legacy/surface-standalone`** | Pre-flake standalone Surface Laptop 3 config (hostname `nixos`, Plasma 6, stateVersion 24.05). |

`os-rebuild` and `hearth-deploy` use **whatever branch is checked out** in `~/.config/nixos`. They print the branch and whether it is stable (`main`) or unstable (`dev`). They do not switch branches.

- New system: clone defaults to `main`, stay there until you opt into daily work (`git switch dev`).
- Daily driver (Tawa today): check out `dev`. Post-rebuild commits stay on `dev`.
- `hearth-deploy` **builds** the builder's checkout. **switch / boot / dry-activate** default to `origin/deploy/hearth` (Hearth's deploy pin), not Tawa's dirty `dev`. Promotion = fast-forward `deploy/hearth`. Escape hatch: `hearth-deploy switch --from-checkout` (warns; still path-filters). Shared-tree touches (`common/`, `home/`, `profiles/`, `flake.nix`, `flake.lock`) vs `origin/main` are refused unless `HEARTH_DEPLOY_ALLOW_SHARED=1` or a commit trailer `Hearth-Deploy: allow-shared`. Activator is still `nixos-rebuild --target-host` (deploy-rs cannot `boot`).
- `legacy/surface-standalone` is named above as the pre-flake Surface rollback. It is **not** on `origin` today.
- Promote: merge or fast-forward `dev` → `main` (Conveyor release, or a deliberate local merge), then hosts that should be stable `git switch main`.

Remote: **`https://github.com/ngrayson/nixos.git`**.

To compare against the old tree: `git log legacy/previous-machine --oneline` (after `git fetch`).

## Rebuilding from this directory

Use the guided helper (zsh alias `os-rebuild`):

```bash
os-rebuild switch                     # current hostname, current branch
os-rebuild build --host Theseus       # another host, build only
```

Direct equivalent:

```bash
sudo nixos-rebuild switch --flake ~/.config/nixos#<hostname>
```

The flake is Git-backed: tracked dirty files are included in builds; untracked files are invisible until `git add`.

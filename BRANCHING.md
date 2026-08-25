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
- `hearth-deploy` **builds** the builder's checkout. **boot / dry-activate** default to `origin/deploy/hearth` (Hearth's deploy pin), not Tawa's dirty `dev`. Interactive **switch** asks for the pin, the checkout, or a fast-forward of the pin to `origin/dev`; `--yes` keeps the pin. Promotion = fast-forward `deploy/hearth`. Escape hatch: `hearth-deploy switch --from-checkout` (warns; still path-filters). Shared-tree touches (`common/`, `home/`, `profiles/`, `flake.nix`, `flake.lock`) vs `origin/main` are refused — see [Shipping a shared-tree change to Hearth](#shipping-a-shared-tree-change-to-hearth). Activator is still `nixos-rebuild --target-host` (deploy-rs cannot `boot`).
- `legacy/surface-standalone` is named above as the pre-flake Surface rollback. It is **not** on `origin` today.
- Promote: merge or fast-forward `dev` → `main` (Conveyor release, or a deliberate local merge), then hosts that should be stable `git switch main`.

Remote: **`https://github.com/ngrayson/nixos.git`**.

To compare against the old tree: `git log legacy/previous-machine --oneline` (after `git fetch`).

## Shipping a shared-tree change to Hearth

`hearth-deploy` path-filters the pin against `origin/main` — the **stable** lane, not `dev`. So a shared-tree touch is refused because it has not been promoted yet, and **promoting is the fix, not the override**. `common/`, `home/`, and `profiles/` also feed Tawa and Theseus, so the guard stops headless Hearth from being the first machine to prove a change that will land on the machines you sit at.

```bash
os-rebuild switch                       # 1. prove it on this workstation first
gh pr create --base main --head dev     # 2. promote (or a deliberate local merge)
git fetch origin                        # 3. after it merges
git push origin origin/dev:deploy/hearth  # 4. fast-forward the pin
hearth-deploy switch                    # 5. filter passes, no override
                                        #    (or pick "Fast-forward" in switch to do 4 + 5)
```

Once the change is on `main`, `origin/main...deploy/hearth` contains only Hearth-only paths and the filter is silent. Hearth-only work (`hosts/Hearth/`, `secrets/`, `scripts/hearth-*`) can fast-forward `deploy/hearth` ahead of `main` freely and never trips it.

**Promote with a merge, not a squash.** The filter uses a three-dot range, so it needs `dev`'s history reachable from `main`. A squashed promotion leaves the merge base where it was and the deploy is still refused.

`HEARTH_DEPLOY_ALLOW_SHARED=1` and the `Hearth-Deploy: allow-shared` trailer are for the deliberate exception: a shared file changed *for* Hearth that you want there before promoting. Prefer the trailer — it records the decision in history where `git log` shows it, instead of only in one shell. Neither is a substitute for activating the change on Tawa.

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

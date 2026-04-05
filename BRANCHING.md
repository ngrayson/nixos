# Branch layout

| Branch | Purpose |
|--------|---------|
| **`main`** | Current machine: Framework (**Theseus**), `~/.config/nixos` — active config. |
| **`legacy/previous-machine`** | Snapshot of **GitHub `main` before 2026-04** (prior NixOS install history). |

Remote: **`https://github.com/ngrayson/nixos.git`** (`git remote rename nixos origin` if you prefer the usual name).

To compare against the old tree: `git log legacy/previous-machine --oneline` (after `git fetch`).

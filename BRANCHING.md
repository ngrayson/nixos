# Branch layout

| Branch | Purpose |
|--------|---------|
| **`main`** | All hosts as named flake outputs: **Tawa** (desktop), **Theseus** (Framework laptop), **Hearth** (Surface Laptop 3 media host), **Gcp** (cloud). Each machine builds its own `nixosConfigurations.<hostname>`. |
| **`legacy/previous-machine`** | Snapshot of **GitHub `main` before 2026-04** (prior NixOS install history). |
| **`legacy/surface-standalone`** | Pre-flake standalone Surface Laptop 3 config (hostname `nixos`, Plasma 6, stateVersion 24.05). |

Remote: **`https://github.com/ngrayson/nixos.git`** (`git remote rename nixos origin` if you prefer the usual name).

To compare against the old tree: `git log legacy/previous-machine --oneline` (after `git fetch`).

## Rebuilding from this directory

Use the guided helper (zsh alias `os-rebuild`):

```bash
os-rebuild switch                     # current hostname
os-rebuild build --host Theseus       # another host, build only
```

Direct equivalent:

```bash
sudo nixos-rebuild switch --flake ~/.config/nixos#<hostname>
```

The flake is Git-backed: tracked dirty files are included in builds; untracked files are invisible until `git add`.

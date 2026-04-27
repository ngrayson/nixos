# Branch layout

| Branch | Purpose |
|--------|---------|
| **`main`** | Desktop **Tawa** (`hosts/Tawa/`) is the default root import; **Theseus** (`hosts/Theseus/`) is the Framework laptop entry — set **`NIXOS_CONFIG`** to that path on the laptop. |
| **`legacy/previous-machine`** | Snapshot of **GitHub `main` before 2026-04** (prior NixOS install history). |

Remote: **`https://github.com/ngrayson/nixos.git`** (`git remote rename nixos origin` if you prefer the usual name).

To compare against the old tree: `git log legacy/previous-machine --oneline` (after `git fetch`).

## `nixos-rebuild` from this directory

`-I` must set the **`nixos-config`** search path, not a bare file path. Examples:

- `NIXOS_CONFIG=$HOME/.config/nixos/configuration.nix nixos-rebuild dry-build`
- `nixos-rebuild dry-build -I nixos-config=$HOME/.config/nixos/configuration.nix`

Using **`-I ~/.config/nixos/configuration.nix`** without the **`nixos-config=`** prefix fails with `file 'nixos-config' was not found in the Nix search path`.

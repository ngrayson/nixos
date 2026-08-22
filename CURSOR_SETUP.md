# Cursor Install (This NixOS Setup)

The IDE is **`pkgs.code-cursor`** in [`profiles/workstation.nix`](./profiles/workstation.nix). Desktop/Albert launchers are owned by [`home/xdg/data.nix`](./home/xdg/data.nix) (templates in [`desktop/applications/cursor.desktop`](./desktop/applications/cursor.desktop)). Do not point those entries at a local AppImage.

Conveyor codespaces: pick an available machine type in WizOs Project Settings. `.devcontainer/conveyor/setup.sh` runs `nix flake check` only — never `nixos-rebuild`.

1. Rebuild so `cursor` is on PATH: `os-rebuild switch` (or `sudo nixos-rebuild switch --flake ~/.config/nixos#<hostname>`).
2. In Cursor, run **Install Cursor CLI** from the command palette (agent shim).
3. Verify the shim exists:
   - `ls -l ~/.local/bin/cursor`
4. Verify agent command works:
   - `~/.local/bin/cursor agent --help`

## Notes for this repo

- `agent`/`agent-new` zsh aliases in [`home/programs/zsh.nix`](./home/programs/zsh.nix) call `~/.local/bin/cursor-agent` directly.
- This avoids PATH issues on fresh systems where `cursor` is not globally available yet.
- Re-apply config after migrating: `os-rebuild switch` (or `sudo nixos-rebuild switch --flake ~/.config/nixos#<hostname>`)

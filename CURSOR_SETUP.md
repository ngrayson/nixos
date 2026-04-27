# Cursor Install (This NixOS Setup)

1. Download the Linux Cursor AppImage from [cursor.com/download](https://cursor.com/download) and run it once.
2. In Cursor, run **Install Cursor CLI** from the command palette.
3. Verify the shim exists:
   - `ls -l ~/.local/bin/cursor`
4. Verify agent command works:
   - `~/.local/bin/cursor agent --help`

## Notes for this repo

- `agent`/`agent-new` zsh aliases in [`home/programs/zsh.nix`](./home/programs/zsh.nix) call `~/.local/bin/cursor agent ...` directly.
- This avoids PATH issues on fresh systems where `cursor` is not globally available yet.
- Re-apply config after migrating: `sudo nixos-rebuild switch -I nixos-config=$HOME/.config/nixos/configuration.nix`

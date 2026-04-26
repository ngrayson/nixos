# User `.desktop` launchers (Plasma / XDG)

Copy **custom** entries here (same file names you want in the app menu). Home Manager links each `*.desktop` in this directory to `~/.local/share/applications/` on `nixos-rebuild`.

- **Do not** duplicate launchers that **apps already manage** (e.g. Cursor, Discord) unless you want Nix to own that file—updates from the app may expect to rewrite them.
- **Exec=** and **Icon=** should use paths that exist on every machine: `$HOME/...`, `~/.local/bin/...`, or a Nix **store** path if the program is in `environment.systemPackages` / `home.packages`.
- On a new install, re-run `sudo nixos-rebuild switch` after `git pull`.

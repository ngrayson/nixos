# Hearth: Surface Pro migration to flake repo + Jellyfin media host

Plan for migrating this Microsoft Surface Pro from its standalone NixOS 24.05
config to the multi-host flake repo (https://github.com/ngrayson/nixos), as the
new host **Hearth** — a lightweight Hyprland media-host machine running Jellyfin.

## Decisions (confirmed 2026-08-21)

| Decision | Choice |
|----------|--------|
| Hostname / flake output | `Hearth` |
| UI | Hyprland + slim home-manager (same UX/theming as Tawa/Theseus, no Steam/Slippi/gaming/heavy apps, no VPN stack) |
| Migration | In-place: switch `~/.config/nixos` to the flake repo; **preserve this machine's generated `hardware-configuration.nix`** |
| Theme to preserve | Terminal palette as seen in fastfetch — Konsole **"Ghost Color Scheme"** — plus desktop wallpaper `~/Documents/Tomes/_assets/telePole.jpg` |
| Media role | Jellyfin only at first; smart-home/media research is low priority (phase 6) |
| Hard requirement | Tawa, Theseus, Gcp must keep functional parity — verified by building all hosts before/after every shared-file change |

## Phases

| Phase | Doc | Outcome |
|-------|-----|---------|
| 0 | (this doc, "Safety" below) | Old config snapshotted and recoverable |
| 1 | [01-phase1-repo-migration.md](./01-phase1-repo-migration.md) | `~/.config/nixos` is the flake repo; `Hearth` host boots from it |
| 2 | [02-phase2-slim-desktop-profile.md](./02-phase2-slim-desktop-profile.md) | Hyprland session with slim home-manager, no heavy apps |
| 3 | [03-phase3-theming-ghost.md](./03-phase3-theming-ghost.md) | Ghost scheme + telePole wallpaper wired through the repo theme system |
| 4 | [04-phase4-touchpad-palm-rejection.md](./04-phase4-touchpad-palm-rejection.md) | Palm rejection / disable-while-typing works on the Type Cover |
| 5 | [05-phase5-jellyfin.md](./05-phase5-jellyfin.md) | Jellyfin serving media; lid-closed operation as a server |
| 6 | [06-research-smart-home.md](./06-research-smart-home.md) | Candidate list for audio / lighting / plant-monitoring services |

Phases 1-2 must land together before the first `switch` (phase 1 alone has no
usable session config). Phases 3-5 are independent of each other and can land
in any order. Phase 6 is research only.

## Phase 0: Safety (before anything else)

1. Commit the current standalone tree and keep it on a branch:
   `git add -A && git commit -m "final standalone Surface config"` then
   `git branch legacy/surface-standalone`.
2. Copy `hardware-configuration.nix` somewhere safe (it will move to
   `hosts/Hearth/hardware-configuration.nix`).
3. Note the current working generation (`nixos-rebuild list-generations`);
   rollback via the systemd-boot menu remains available throughout.
4. Optionally push `legacy/surface-standalone` to the flake repo remote,
   mirroring the existing `legacy/previous-machine` convention in BRANCHING.md.

## Parity guardrail (applies to every phase)

Before and after any change that touches a shared file (`common/`, `home/`,
`flake.nix`, `flake.lock`):

```bash
nix build .#nixosConfigurations.Tawa.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.Theseus.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.Gcp.config.system.build.toplevel --dry-run
```

For purely additive changes the Tawa/Theseus/Gcp toplevel store paths must be
byte-identical before/after. Where a shared file must be edited (theme
`hosts.nix` is additive-safe; anything else needs justification), record the
before/after paths in the phase doc.

## Parity record (2026-08-21, after Hearth additive changes)

Compared dirty working tree vs `origin/main` (`d63adfd`). Shared-file edits
were additive only (`flake.nix` host entry, `home/theme/{default,hosts}.nix`
Ghost/Hearth registration, `BRANCHING.md`).

| Host | origin/main drv | after Hearth work | Match |
|------|-----------------|-------------------|-------|
| Tawa | `/nix/store/a3m8ka2fvd8r7656ry73ilnff7grcrrf-nixos-system-Tawa-26.05.20260819.b18a4b9.drv` | same | yes |
| Theseus | `/nix/store/a63x9gl2srr5halay14pap6d58rpxbr3-nixos-system-Theseus-26.05.20260819.b18a4b9.drv` | same | yes |
| Gcp | `/nix/store/l40kzqj5g2d2nfvy2jrvpj9yq0hd3xfk-nixos-system-Gcp-google-compute-26.05.20260819.b18a4b9.drv` | same | yes |

Tawa/Theseus still match after the Hearth-only bind split in
`home/wayland/hyprland.nix` (albert / discord / obsidian omitted on Hearth,
same bind list and order on Tawa/Theseus).

## First rebuild (2026-08-21)

Hearth toplevel built:

- store path: `/nix/store/klyqnzmqp3j60ivqn2cmh5gb1q49jxck-nixos-system-Hearth-26.05.20260819.b18a4b9`
- closure: **10.0 GiB**
- jellyfin unit present; Hyprland `disable_while_typing=true`

Activation needs root. From a normal terminal (not a no-new-privileges sandbox):

```bash
sudo nixos-rebuild switch --flake ~/.config/nixos#Hearth
```

Or `os-rebuild switch --host Hearth --no-commit` after the first login on the
new generation. Old Plasma generations remain in the systemd-boot menu.

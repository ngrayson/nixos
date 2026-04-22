# Phase 3 — Home Manager (user-level config)

**Goal:** Move **dotfiles, user packages, and per-user options** into reproducible config, separate from full-system `configuration.nix`.

**NixOS module + minimal `home.nix` (scaffold):** Your machine may already import Home Manager in **`configuration.nix`** and ship a tiny **`home.nix`** — enough for **`nixos-rebuild`** to run HM, **without** having moved Kitty/zsh/git into HM yet. That **scaffold** is **not** the same as completing Phase 3. See [LOCKED — Q4](./LOCKED.md#decisions-authoritative) and [06 — § D](./06-implementation-checklist.md#d--home-manager-phase-d-migration-deferred).

**Execution (2026-04):** **Migrating** real user config into HM (**Phase D**) is **deferred** until **Phase C** feels stable and important paths are **NixOS** + **`~/.config`** (moving off **chezmoi**; see [LOCKED — Dotfiles strategy](./LOCKED.md#execution-note-rolling)).

## Concepts (read once, check when understood)

- [ ] **What Home Manager is:** Declarative config for **your user** (programs, services, files), built from the same `nixpkgs` revision as the system (when set up that way).
- [ ] **Where it runs:** Usually `home-manager switch` as your user; can be integrated as a **NixOS module** (`home-manager.users.<name> = { ... }`) for one-shot system rebuilds.
- [ ] **Idempotence:** Running `switch` repeatedly should converge to the same result (no manual file editing for managed paths).

## Installation path (pick one)

**Roadmap (decisions Q3–Q4):** Use **classic** `configuration.nix` + **`nixos-rebuild`** first; learn Home Manager with **standalone** **`home-manager switch`** — **no flakes required**. Move to the **NixOS module** later if you want one command to apply system + user.

- [ ] **Standalone Home Manager** — install the `home-manager` tool; `~/.config/home-manager/home.nix` (typical). **Preferred while learning.**
- [ ] **NixOS module** — Home Manager declared inside `configuration.nix` so `nixos-rebuild` also applies user config (optional after you are comfortable with standalone).

## Chezmoi dotfiles (existing base)

You already maintain **[ngrayson/debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main)** with **chezmoi** templates for **Debian** and **Omarchy** (a Linux distribution). On NixOS, reuse that repo as the baseline for **shell aliases**, **Kitty** (and other) configs, and shared snippets — then reconcile with NixOS reality.

**Decision (Q5):** **Hybrid (c)** — **one owner per path.** **Current:** **one-time chezmoi apply**, then **migrate** into **`configuration.nix`**; **`.chezmoiignore`** as paths flip to NixOS ([LOCKED](./LOCKED.md#execution-note-rolling)). **After Home Manager:** chezmoi for cross-distro templates / secrets only where needed; HM owns **`programs.kitty`**, **`programs.zsh`**, etc. Keep an **ownership list** and **`.chezmoiignore`** / **`.gitignore`** as appropriate.

- [ ] **Inventory** — list which templates/data apply unchanged vs need a **NixOS** (or distro-agnostic) branch in `.chezmoi.toml` / template conditions.
- [ ] **Path and package assumptions** — replace FHS-only paths or `apt`-specific bits with NixOS equivalents where needed.
- [ ] **Ownership list** — for each managed path, note **chezmoi** vs **HM**; update when you move a file from one to the other.
- [ ] **Track parity** — keep Debian/Omarchy/NixOS templates in sync enough that you are not maintaining three unrelated configs.

## First useful `home.nix` goals

- [ ] **Terminal** — `programs.kitty.enable = true` (and options) so the **default terminal** in Phase 2 is backed by declarative config.
- [ ] **Fastfetch** — **`~/.config/fastfetch/config.jsonc`** is **user-maintained** today (not chezmoi). When you adopt HM, **migrate ownership** via **`xdg.configFile."fastfetch/config.jsonc".source`** (or **`text`**) in the repo, or use **`programs.fastfetch`** if your **Home Manager / nixpkgs** version exposes it and it fits. Then HM is the single owner of that path.
- [ ] **zsh** — `programs.zsh.enable = true`; login shell via `users.users.<name>.shell` on NixOS or `programs.zsh` + HM; **plugins** via Home Manager where supported, e.g. `autosuggestion.enable`, `syntaxHighlighting.enable`, completion packages — mirror the “essential plugins” list from Phase 2.
- [ ] **Git** — `programs.git` with user name/email (or keep secrets out of the repo with `sops-nix` later).
- [ ] **Editor** — minimal `programs.neovim` or link to your config.
- [ ] **Session env** — e.g. `home.sessionVariables.TERMINAL` pointing at `kitty` if your WM/scripts read it.

## Practice checklist

- [ ] Change one option (e.g. a shell alias), run **switch**, open a **new terminal**, verify the change.
- [ ] Intentionally **break** something small, read the error, **rollback** or fix forward (builds confidence).

## Hygiene

- [ ] **Version control** — put `home.nix` (and flake if used) in **git**; avoid committing secrets.
- [ ] **Secrets** — plan for API keys (password store, `sops-nix`, or agenix) before putting tokens in plain text.

## Done when

- [ ] You can add a **user program or dotfile** via Home Manager without manual copying on every machine.
- [ ] You know whether you are on **standalone** or **NixOS module** integration and how to rebuild.
- [ ] **Chezmoi + NixOS** story is clear: how [debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main) feeds this machine and what Home Manager owns.

## Your notes (commands, file paths)

<!-- e.g. home-manager switch | flake: ... | chezmoi data keys for nixos -->

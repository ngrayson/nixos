# Phase 3 — Home Manager (user-level config)

**Goal:** Move **dotfiles, user packages, and per-user options** into reproducible config, separate from full-system `configuration.nix`.

## This repo (`~/.config/nixos`)

**NixOS module** integration: [`common/system.nix`](../../common/system.nix) sets `home-manager.users.wiz = import ../home.nix`.

- Root **[`home.nix`](../../home.nix)** — Home Manager entry only: `imports = [ ./home ];`.
- **[`home/default.nix`](../../home/default.nix)** — imports topic modules: [`session.nix`](../../home/session.nix), [`programs/`](../../home/programs/), [`wayland/hyprland.nix`](../../home/wayland/hyprland.nix), [`services/hypridle.nix`](../../home/services/hypridle.nix), [`xdg/`](../../home/xdg/), [`hypr/scripts.nix`](../../home/hypr/scripts.nix), [`lib/`](../../home/lib/), etc.

**Historical roadmap text:** The original Framework plan assumed a *minimal* `home.nix` scaffold and **Phase D** migration later. On this machine, **Phase D–style** content is **already** under **`./home/`** — see [LOCKED — live repo note](./LOCKED.md#live-repo-note-2026-04) and **[`MIGRATION.md`](../../MIGRATION.md)**.

## Concepts (read once, check when understood)

- [ ] **What Home Manager is:** Declarative config for **your user** (programs, services, files), built from the same `nixpkgs` revision as the system (when set up that way).
- [ ] **Where it runs:** Usually `home-manager switch` as your user; integrated here as a **NixOS module** (`home-manager.users.<name> = import …`) for one-shot **`nixos-rebuild`**.
- [ ] **Idempotence:** Running `switch` repeatedly should converge to the same result (no manual file editing for managed paths).

## Installation path (pick one)

**This repo:** **NixOS module** only — no standalone `~/.config/home-manager/home.nix` required.

- [ ] **Standalone Home Manager** — install the `home-manager` tool; `~/.config/home-manager/home.nix` (typical). **Optional** for experiments on other machines.
- [x] **NixOS module** — Home Manager declared in [`common/system.nix`](../../common/system.nix) so `nixos-rebuild` also applies user config.

## Chezmoi dotfiles (existing base)

You already maintain **[ngrayson/debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main)** with **chezmoi** templates for **Debian** and **Omarchy** (a Linux distribution). On NixOS, reuse that repo as the baseline for **shell aliases**, **Kitty** (and other) configs, and shared snippets — then reconcile with NixOS reality.

**Decision (Q5):** **Hybrid (c)** — **one owner per path.** **Current:** **one-time chezmoi apply**, then **migrate** into **`configuration.nix`** / **`./home/`**; **`.chezmoiignore`** as paths flip to NixOS ([LOCKED](./LOCKED.md#execution-note-rolling)). **This repo:** chezmoi removed from system packages; HM owns user config under **`./home/`**. Keep an **ownership list** and **`.chezmoiignore`** / **`.gitignore`** as appropriate.

- [ ] **Inventory** — list which templates/data apply unchanged vs need a **NixOS** (or distro-agnostic) branch in `.chezmoi.toml` / template conditions.
- [ ] **Path and package assumptions** — replace FHS-only paths or `apt`-specific bits with NixOS equivalents where needed.
- [ ] **Ownership list** — for each managed path, note **chezmoi** vs **HM**; update when you move a file from one to the other. **Live table:** [MIGRATION.md](../../MIGRATION.md#home-manager-path-ownership-audit-tawa--confignixos).
- [ ] **Track parity** — keep Debian/Omarchy/NixOS templates in sync enough that you are not maintaining three unrelated configs.

## First useful Home Manager goals (reference)

**This repo status:** Many items below are **done** under **`./home/`** (Kitty via `xdg.configFile` in `home/xdg/config.nix`, not `programs.kitty`).

- [x] **Terminal** — Kitty config from repo [`kitty/`](../../kitty/) via **`xdg.configFile`** (`home/xdg/config.nix`); **`kitty`** also in **`environment.systemPackages`** for Plasma launchers.
- [x] **Fastfetch** — **`xdg.configFile`** from [`fastfetch/`](../../fastfetch/) in **`home/xdg/config.nix`**.
- [x] **zsh** — **`programs.zsh`** in **`home/programs/zsh.nix`**; login shell via `users.users.wiz.shell` in NixOS.
- [x] **Git** — **`programs.git`** in **`home/programs/git.nix`**.
- [ ] **Editor** — minimal `programs.neovim` or link to your config (optional).
- [x] **Session env** — **`home.sessionVariables`** in **`home/session.nix`** (`TERMINAL`, `EDITOR`, …).

## Practice checklist

- [ ] Change one option (e.g. a shell alias), run **`sudo nixos-rebuild switch`**, open a **new terminal**, verify the change.
- [ ] Intentionally **break** something small, read the error, **rollback** or fix forward (builds confidence).

## Hygiene

- [ ] **Version control** — commit root **`home.nix`** and the **`./home/`** tree; avoid committing secrets.
- [ ] **Secrets** — plan for API keys (password store, `sops-nix`, or agenix) before putting tokens in plain text.

## Done when

- [ ] You can add a **user program or dotfile** via Home Manager without manual copying on every machine.
- [ ] You know that **`nixos-rebuild`** applies system + HM via the NixOS module.
- [ ] **Chezmoi + NixOS** story is clear: how [debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main) feeds this machine and what Home Manager owns.

## Your notes (commands, file paths)

<!-- e.g. nixos-rebuild | flake: ... | chezmoi data keys for nixos -->

# NixOS on Framework — plan locked

**Status:** **LOCKED**  
**Locked on:** 2026-04-05  
**Machine:** Framework laptop — **`Theseus`** (user **`wiz`**)

This file is the **frozen snapshot** of agreed decisions. Detailed rationale, risks, and phase text stay in [00-audit-priorities-and-risks.md](./00-audit-priorities-and-risks.md) and phases **01–05**.

**To change the plan:** update the phase files and audit as needed, then **revise this file** (or add `LOCKED-YYYY-MM-DD.md`) so “locked” always points at a clear baseline.

---

## Live repo note (2026-04)

**Home Manager** for user **`wiz`** is **modular**: root [`home.nix`](../../home.nix) only does `imports = [ ./home ];`; real options live under [`home/`](../../home/) ([`home/default.nix`](../../home/default.nix) imports `session.nix`, `programs/`, `wayland/hyprland.nix`, `services/hypridle.nix`, `xdg/`, `hypr/scripts.nix`, `lib/`, etc.). Authoritative path ownership: **[`MIGRATION.md`](../../MIGRATION.md)**.

The **decision table** below is the **2026-04-05** Framework snapshot. **Row 4** described a *minimal* `home.nix` scaffold and **Phase D** deferred; on the **live** machine that snapshot is **out of date** — Kitty (via `xdg.configFile`), zsh, git, Hyprland, Quickshell, hypridle, and related user config are already in HM under **`./home/`**.

---

## Decisions (authoritative)

| # | Topic | Locked choice |
|---|--------|----------------|
| 1 | WM | **KDE Plasma (Wayland) + tiling** — daily driver; **Sway** / other wlroots WMs **not** planned |
| 2 | Display | **Wayland** primary; **XWayland** for games; **KDE portal** + **PipeWire** for screen sharing on Plasma (add **wlr** portal only if you change compositor family) |
| 3 | Nix layout | **Classic** — `nixos-rebuild` + **`-I nixos-config=…`** (or import); **channels** for `nixpkgs`; **flakes later** |
| 4 | Home Manager | **Original lock (2026-04-05):** **NixOS module** + minimal **`home.nix`** (scaffold); **Phase D** into HM — **deferred**. **Live `~/.config/nixos`:** modular **[`./home/`](../../home/)** (root [`home.nix`](../../home.nix) imports it); Phase D–style migration **done** — [Live repo note (2026-04)](#live-repo-note-2026-04). Learning path was **standalone** `home-manager switch` first; this system uses the **module** so one `nixos-rebuild` applies system + HM |
| 5 | Dotfiles | **Hybrid (c)** — **one owner per path**; **chezmoi** + **HM**; **ownership list** in git |
| 6 | zsh | **HM `programs.zsh`** primary; **oh-my-zsh** only via HM if wanted |
| 7 | Identity | **User `wiz`**, **`networking.hostName = "Theseus"`** |
| 8 | Packages | Restore **dev → comms/productivity → gaming** (gaming last, separate change) |
| 9 | Editors | **`micro`** for `EDITOR` / `VISUAL` / `SYSTEMD_EDITOR`; **VS Code or VSCodium**, **Cursor**; **Glow** for markdown |
| 10 | Memory | **Existing swap only** — **no `zramSwap`** |

---

## Execution spine (unchanged)

**Action list:** [06-implementation-checklist.md](./06-implementation-checklist.md) (checkboxes A→E).

1. **Bootstrap** — [01](./01-baseline-nix-packages.md), hardware, `stateVersion`, config location.  
2. **Base system** — [02](./02-functional-improvements.md) + [05](./05-previous-nixos-config-extract.md): network, audio, BT, print, portals, browser.  
3. **Session** — **Plasma (Wayland) + tiling**, **Kitty**, **zsh**, focus-follows-mouse, hotkeys.  
4. **Home Manager** — [03](./03-home-manager.md), chezmoi boundaries.  
5. **Rice** — [04](./04-ricing.md).

### Execution note (rolling)

**Historical (2026-04-05 lock):** **Phase D** was described as moving user programs into a monolithic **`home.nix`**, deferred until **Phase C** settled.

**Live `~/.config/nixos` repo:** User programs and dotfiles are in **Home Manager** under modular **[`./home/`](../../home/)** (root [`home.nix`](../../home.nix) only imports that tree). See **[Live repo note (2026-04)](#live-repo-note-2026-04)** and **[`MIGRATION.md`](../../MIGRATION.md)**. [06](./06-implementation-checklist.md) § D is updated to match.

**Dotfiles strategy (rolling)** — two phases:

1. **Bootstrap (chezmoi once):** **`chezmoi init`** + **`chezmoi apply`** from [debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main) to **materialize the full dotfile tree** under `$HOME` — one coherent starting point from your existing templates.
2. **Shift NixOS-centric:** **re-create** what you care about in **`configuration.nix`** (and later **`environment.sessionVariables`**, **`programs.*`**, optional HM): Kitty, git defaults, extra aliases, etc. For each path you move, add it to **`.chezmoiignore`** (or remove the template) so **chezmoi stops owning it** and **NixOS is the source of truth**. Avoid long-term **double ownership** of the same file.

Until that migration settles, **`programs.zsh`** in **`configuration.nix`** can stay minimal (aliases, oh-my-zsh); **merge carefully** with any chezmoi-managed **`~/.zshrc`** so you do not define the same behavior twice.

---

## Linked repos

- Chezmoi templates: [ngrayson/debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main)

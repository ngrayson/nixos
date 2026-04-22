# NixOS on Framework — plan locked

**Status:** **LOCKED**  
**Locked on:** 2026-04-05  
**Machine:** Framework laptop — **`Theseus`** (user **`wiz`**)

This file is the **frozen snapshot** of agreed decisions. Detailed rationale, risks, and phase text stay in [00-audit-priorities-and-risks.md](./00-audit-priorities-and-risks.md) and phases **01–05**.

**To change the plan:** update the phase files and audit as needed, then **revise this file** (or add `LOCKED-YYYY-MM-DD.md`) so “locked” always points at a clear baseline.

---

## Decisions (authoritative)

| # | Topic | Locked choice |
|---|--------|----------------|
| 1 | WM | **KDE Plasma (Wayland) + tiling** — daily driver; **Sway** / other wlroots WMs **not** planned |
| 2 | Display | **Wayland** primary; **XWayland** for games; **KDE portal** + **PipeWire** for screen sharing on Plasma (add **wlr** portal only if you change compositor family) |
| 3 | Nix layout | **Classic** — `nixos-rebuild` + **`-I nixos-config=…`** (or import); **channels** for `nixpkgs`; **flakes later** |
| 4 | Home Manager | **NixOS module** + minimal **`home.nix`** (scaffold only); **Phase D** — move Kitty, zsh, git, etc. into HM per [03](./03-home-manager.md) — **deferred**. Learning path was **standalone** `home-manager switch` first; the live system uses the **module** so one `nixos-rebuild` applies system + HM |
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

**Home Manager migration (Phase D)** — moving user programs into **`home.nix`** — is **deferred** until **Phase C** is stable and dotfiles are mostly **NixOS-managed** (see below). The nixos repo may already load the **Home Manager NixOS module** with a **minimal** `home.nix` (`stateVersion`, `programs.home-manager.enable`) so activation is unified with `nixos-rebuild`; that is **scaffold**, not Phase D. Long-term targets for **Q4–Q6** stay in the table above; **Phase D** in [06](./06-implementation-checklist.md) tracks **migration** work.

**Dotfiles strategy (rolling)** — two phases:

1. **Bootstrap (chezmoi once):** **`chezmoi init`** + **`chezmoi apply`** from [debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main) to **materialize the full dotfile tree** under `$HOME` — one coherent starting point from your existing templates.
2. **Shift NixOS-centric:** **re-create** what you care about in **`configuration.nix`** (and later **`environment.sessionVariables`**, **`programs.*`**, optional HM): Kitty, git defaults, extra aliases, etc. For each path you move, add it to **`.chezmoiignore`** (or remove the template) so **chezmoi stops owning it** and **NixOS is the source of truth**. Avoid long-term **double ownership** of the same file.

Until that migration settles, **`programs.zsh`** in **`configuration.nix`** can stay minimal (aliases, oh-my-zsh); **merge carefully** with any chezmoi-managed **`~/.zshrc`** so you do not define the same behavior twice.

---

## Linked repos

- Chezmoi templates: [ngrayson/debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main)

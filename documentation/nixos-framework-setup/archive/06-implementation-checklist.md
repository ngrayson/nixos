# Implementation checklist — continue from LOCKED

Use this **after** [LOCKED.md](./LOCKED.md). Work **top to bottom**; check items as you go. Deep detail stays in phases **01–04** and [00-audit-priorities-and-risks.md](./00-audit-priorities-and-risks.md).

## Current status (rolling)

**Last updated:** 2026-04-26

| Area | State |
|------|--------|
| **A — Bootstrap** | Complete. |
| **B — Base system** | **Functionally complete.** **Optional later:** measure suspend **drain / `deep`**, **hotel** Wi‑Fi retest for FrootVPN; see [02 — Low-power](./02-functional-improvements.md#low-power-suspend-investigation). |
| **C — Session** | **Complete** (session polish as of 2026-04): **Kitty**, **zsh**, **Plasma + tiling**, **hotkeys** and **ergonomics** (incl. min-width / HiDPI) at a level you are happy with; table in [02 — WM / hotkey notes](./02-functional-improvements.md#wm--hotkey-notes) reflects real bindings. **`outside`** [deferred](./08-dotfiles-migration-plan.md#deferred--later). On the **live** `~/.config/nixos` repo, user session pieces also include **Hyprland** + **Quickshell** + **hypridle** under **[`home/`](../../home/)** (see [LOCKED — live repo note](./LOCKED.md#live-repo-note-2026-04)). |
| **D** | **Complete** on the live machine: user programs and dotfiles live in modular **Home Manager** under **[`./home/`](../../home/)** (root [`home.nix`](../../home.nix) re-exports `imports = [ ./home ]`). Historical checklist text in [§ D](#d--home-manager-phase-d-migration-deferred) below kept for context. |
| **E — Rice** | **Complete** (as of 2026-04): **LilacAsh**-aligned pass across **Kvantum**, **Kitty**, **Cursor**, **Obsidian**, **micro**; `themes/links/`. **Stylix** not required for “done” — optional Nix-wide theme later per [04](./04-ricing.md#strategy--plasma-first-then-stylix). |

---

## A — Bootstrap (system identity + Nix workflow)

- [x] **`hardware-configuration.nix`** — generated for this Framework; reviewed (disk, initrd, kernel modules).
- [x] **`system.stateVersion`** — set for **this** install (do not copy an old machine blindly).
- [x] **`networking.hostName = "Theseus";`**
- [x] **User `wiz`**: `isNormalUser = true`, `shell = pkgs.zsh`, groups: `wheel`, `networkmanager`, `video` (adjust if needed).
- [x] **Swap:** confirm existing swap; **`zramSwap.enable = false`** or omit `zramSwap` entirely ([Q10](./00-audit-priorities-and-risks.md#q10-zram-and-swap)).
- [x] **Config location:** classic **`nixos-rebuild switch -I nixos-config=/path/to/configuration.nix`** (or import pattern) — **document the path** in your config repo Notes.
- [x] **Smoke test:** `sudo nixos-rebuild switch`, reboot once, confirm **rollback** in boot menu works.
- [x] **Phase 1 cheat sheet (+ `os-rebuild` helper)** — [01 — Notes](./01-baseline-nix-packages.md#notes), [`os-rebuild.sh`](./os-rebuild.sh) (copy in this directory; install to `PATH` as you prefer).
- [x] **os-rebuild installed and approved:** `os-rebuild` runs with guided prompts, formats if desired, shows diffs, saves logs, and user approves the UX.
- [x] **Config repo remote (backups):** the git repository that holds your live NixOS configuration (the directory **`os-rebuild`** uses via **`NIXOS_CONFIG`** / **`NIXOS_DIR`**) has a **remote** (e.g. `origin`) **added and pushed** so your configuration is backed up off the machine, not only in local commits.

---

## B — Base system (network, sound, desktop plumbing)

- [x] **NetworkManager** — `networking.networkmanager.enable = true;`
- [x] **PipeWire** — audio stack; test speakers + mic + Bluetooth audio.
- [x] **Bluetooth** — `hardware.bluetooth.enable` (+ `powerOnBoot` if you want).
- [x] **Printing** — `services.printing.enable` if you use a printer.
- [x] **Locale / timezone** — e.g. `America/Vancouver`, `en_CA.UTF-8` (adjust to taste).
- [x] **Polkit** — `security.polkit.enable = true;` (typical for graphical session).
- [x] **Libinput** — touchpad (`services.libinput.enable` on current NixOS).
- [x] **Browser** — e.g. `programs.firefox.enable = true;` so you have docs online.
- [x] **Portals + screen sharing** — `xdg.portal.enable = true;` + **KDE portal** on Plasma ([Q2](./LOCKED.md)). (**wlr** portal only if you add a wlroots session later — not planned.)
- [x] **Suspend / brightness / dock** — **logind** + **powertop** in config; **session-acceptable** for daily use. **Optional** extra tuning: **drain / `deep`** / dock verification — [02 § Low-power](./02-functional-improvements.md#low-power-suspend-investigation).
- [x] **Fingerprint reader** — `services.fprintd.enable` + **`security.pam.services.*.fprintAuth`**; **enrollment** + **unlock / login / sudo** tests OK ([02 — Fingerprint](./02-functional-improvements.md#fingerprint-fprintd)).

---

## C — Session (Kitty, shell, WM)

- [x] **Kitty** — installed; default terminal in session (`$TERMINAL`, keybinding, `.desktop` / portal).
- [x] **zsh** — **NixOS `programs.zsh`** + **`dot_zshrc` / `~/.zshrc`** aligned (no duplicate OMZ path); theme **`clean`** in `configuration.nix`; **`shellAliases`** (`ns`, `vpn`). Further dotfile moves stay **incremental** ([02 — Oh My Zsh on NixOS](./02-functional-improvements.md#chezmoi-bootstrap-then-nixos-migration)).
- [x] **Compositor path:** **Plasma (Wayland) + tiling** — [Q1](./LOCKED.md); **Sway** not targeted.
- [x] **Tiling + focus-follows-mouse + hotkeys** — documented in one place ([02](./02-functional-improvements.md)); **session polish done** (bindings, conflicts, min-width/HiDPI to satisfaction).
- [x] **Editors:** **`micro`** in env; **VS Code / VSCodium / Cursor**; **Glow** — declared in `configuration.nix` ([Q9](./LOCKED.md)); user-facing shell aliases in **[`home/programs/zsh.nix`](../../home/programs/zsh.nix)**.
- [x] **Cross-app style baseline:** **IosevkaTermSlab NFM** font set in Kitty/Cursor/Obsidian; terminal/UI palette aligned across **Kitty**, **Cursor** (including ANSI), **Obsidian**, and **micro**.
- [x] **Dotfiles → Nix / `~/.config` (this wave):** **Aliases**, **newsboat**, **WM stack removal**, etc. per [08](./08-dotfiles-migration-plan.md). **Ongoing:** **Outside** ([08](./08-dotfiles-migration-plan.md)); **`.local/bin`** ([08](./08-dotfiles-migration-plan.md)). **NixOS:** keep **`~/.config/nixos`** committed/pushed as you already do for **`nixos-rebuild`** — **no chezmoi** workflow. Policy: [LOCKED](./LOCKED.md#execution-note-rolling).

---

<a id="d--home-manager-phase-d-migration-deferred"></a>

## D — Home Manager (Phase D: done on live `~/.config/nixos`)

**Live layout:** NixOS **module** + root **`home.nix`** + modular **[`./home/`](../../home/)** — `nixos-rebuild` applies HM; see [LOCKED — live repo note](./LOCKED.md#live-repo-note-2026-04) and **[`MIGRATION.md`](../../MIGRATION.md)**.

- [x] **NixOS module** + **`./home.nix`** — activates with `nixos-rebuild` ([03](./03-home-manager.md) concepts).
- [x] **Phase D — user programs in HM:** **Kitty** (`xdg.configFile` in `home/xdg/config.nix`), **zsh**, **git**, **`sessionVariables`**, **Hyprland**, **hypridle**, **Quickshell**, etc., under **`./home/`** (not monolithic `home.nix`).
- [ ] **Optional** — standalone **`home-manager switch`** with `~/.config/home-manager/home.nix` for experiments; **not** required if the module is primary.
- [x] **Ownership list** — see **[`MIGRATION.md` — path ownership](../../MIGRATION.md#home-manager-path-ownership-audit-tawa--confignixos)**.

---

## E — Rice

- [x] **Cross-app palette + app configs (manual pass):** LilacAsh colors applied to **Kvantum**, **Kitty**, **Cursor**, **Obsidian**, **micro**.
- [x] **Style config links in repo:** symlink hub created at `themes/links/` for active style files (`kitty`, `Cursor`, `Obsidian`, `micro`, `Kvantum`).
- [x] **Strategy** — [04 — Plasma first, then Stylix](./04-ricing.md#strategy--plasma-first-then-stylix): **Plasma + manual cross-app pass** (LilacAsh / links in `themes/`). **Stylix** left as an **optional** future add-on, not part of this “done.”
- [x] **Investigation** — [04](./04-ricing.md#investigation--theseus-plasma-6--wayland--framework-13) checklist satisfied for **Theseus** (see [04 — investigation checklist](./04-ricing.md#checklist--investigation-in-progress)).
- [x] **Polish** — [04 — Done when](./04-ricing.md#done-when) met; nice-to-haves in [04 — Framework display](./04-ricing.md#framework-display) (night keyboard floor, auto night sync) stay **optional** if you want them later.

---

## Quick reference

| Decision | Where |
|----------|--------|
| All locked choices | [LOCKED.md](./LOCKED.md) |
| Package restore order | [05](./05-previous-nixos-config-extract.md) + [Q8](./00-audit-priorities-and-risks.md#q8-package-restore-priority) |

**Current step:** **Phase D** is **done** on the live repo ([`./home/`](../../home/)). **Elsewhere optional:** **`outside`** [deferred](./08-dotfiles-migration-plan.md#deferred--later); suspend **drain / `deep`**, **hotel** VPN retest — [02 — Low-power](./02-functional-improvements.md#low-power-suspend-investigation), [FrootVPN + Stunnel](./02-functional-improvements.md#frootvpn--stunnel--vortix-theseus); **Stylix** [04](./04-ricing.md#strategy--plasma-first-then-stylix).

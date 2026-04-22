# Implementation checklist — continue from LOCKED

Use this **after** [LOCKED.md](./LOCKED.md). Work **top to bottom**; check items as you go. Deep detail stays in phases **01–04** and [00-audit-priorities-and-risks.md](./00-audit-priorities-and-risks.md).

## Current status (rolling)

**Last updated:** 2026-04-08

| Area | State |
|------|--------|
| **A — Bootstrap** | Complete. |
| **B — Base system** | **Functionally complete** for now. **Deferred (later):** suspend **drain / `deep`** ([02 — Low-power](./02-functional-improvements.md#low-power-suspend-investigation)); **real captive/hotel** Wi‑Fi spot-check for FrootVPN. Otherwise: mic, webcam, portals, **Bluetooth** / **fingerprint**, **VPN** + **FrootVPN stunnel** as documented. |
| **C — Session** | **Kitty** + **`$TERMINAL`**; **zsh / git / shellAliases** Nix-aligned; **fastfetch** in **`~/.config/fastfetch/`**. **Moving off chezmoi** — machine policy in **`configuration.nix`**, ad hoc configs under **`~/.config`**. **[08](./08-dotfiles-migration-plan.md) migration wave** done for current scope; **orphans** in **`~/dotfiles-archive/2026-04-05-orphans/`**. **Hotkey placeholders** in [02](./02-functional-improvements.md#wm--hotkey-notes). **`outside`** via **`cargo install`** — [deferred](./08-dotfiles-migration-plan.md#deferred--later). **Stellarium** push — done. **Home Manager migration (Phase D) deferred**; **minimal `home.nix` scaffold** may exist — [LOCKED](./LOCKED.md#execution-note-rolling). **Tiling min-width** — [02 — Framework ergonomics](./02-functional-improvements.md#framework-ergonomics). |
| **D / E** | **D (move user config into Home Manager)** still **open** (Kitty, zsh, etc. in **`home.nix`**). **E (rice)** now includes a **working LilacAsh cross-app pass**: **Kvantum**, **Kitty**, **Cursor** (workbench + terminal ANSI), **Obsidian theme**, and **micro colorscheme**; shared palette + config links are in `themes/` (see checklist). |

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
- [ ] **Suspend / brightness / dock** — **logind** lid + **`powertop`** in config ([02 § Low-power](./02-functional-improvements.md#low-power-suspend-investigation)) — **deferred:** **drain / `deep`** when you want to tune; brightness/dock sanity when you care.
- [x] **Fingerprint reader** — `services.fprintd.enable` + **`security.pam.services.*.fprintAuth`**; **enrollment** + **unlock / login / sudo** tests OK ([02 — Fingerprint](./02-functional-improvements.md#fingerprint-fprintd)).

---

## C — Session (Kitty, shell, WM)

- [x] **Kitty** — installed; default terminal in session (`$TERMINAL`, keybinding, `.desktop` / portal).
- [x] **zsh** — **NixOS `programs.zsh`** + **`dot_zshrc` / `~/.zshrc`** aligned (no duplicate OMZ path); theme **`clean`** in `configuration.nix`; **`shellAliases`** (`ns`, `vpn`). Further dotfile moves stay **incremental** ([02 — Oh My Zsh on NixOS](./02-functional-improvements.md#chezmoi-bootstrap-then-nixos-migration)).
- [x] **Compositor path:** **Plasma (Wayland) + tiling** — [Q1](./LOCKED.md); **Sway** not targeted.
- [x] **Tiling + focus-follows-mouse + hotkeys** — documented in one place ([02](./02-functional-improvements.md)) — **focus-follows-mouse OK**; **tiling** mostly OK (**min window width** issue — see status table); **WM / hotkey table** scaffolded with **placeholders** — replace **Binding** cells with your real shortcuts when stable.
- [x] **Editors:** **`micro`** in env; **VS Code / VSCodium / Cursor**; **Glow** — declared in `configuration.nix` ([Q9](./LOCKED.md)); **Home Manager optional later**.
- [x] **Cross-app style baseline:** **IosevkaTermSlab NFM** font set in Kitty/Cursor/Obsidian; terminal/UI palette aligned across **Kitty**, **Cursor** (including ANSI), **Obsidian**, and **micro**.
- [x] **Dotfiles → Nix / `~/.config` (this wave):** **Aliases**, **newsboat**, **WM stack removal**, etc. per [08](./08-dotfiles-migration-plan.md). **Ongoing:** **Outside** ([08](./08-dotfiles-migration-plan.md)); **`.local/bin`** ([08](./08-dotfiles-migration-plan.md)). **NixOS:** keep **`~/.config/nixos`** committed/pushed as you already do for **`nixos-rebuild`** — **no chezmoi** workflow. Policy: [LOCKED](./LOCKED.md#execution-note-rolling).

---

## D — Home Manager (Phase D: migration deferred)

**Scaffold (may already be in `configuration.nix`):** NixOS **module** + minimal **`home.nix`** (`stateVersion`, `programs.home-manager.enable`) so `nixos-rebuild` applies HM; see [LOCKED — Q4](./LOCKED.md#decisions-authoritative). That is **not** the same as moving user config into HM.

- [x] **NixOS module** + minimal **`./home.nix`** (or equivalent) — activates with `nixos-rebuild` ([03](./03-home-manager.md) concepts).
- [ ] **Phase D — user programs in HM:** move **Kitty**, **zsh**, **git**, **`sessionVariables`**, and other `programs.*` per [03](./03-home-manager.md) (or keep in `configuration.nix` until ready).
- [ ] **Optional** — standalone **`home-manager switch`** with `~/.config/home-manager/home.nix` for experiments; **not** required if the module is primary.
- [ ] **Ownership list** — NixOS vs **`~/.config`** vs HM — keep current as you migrate.

---

## E — Rice

- [x] **Cross-app palette + app configs (manual pass):** LilacAsh colors applied to **Kvantum**, **Kitty**, **Cursor**, **Obsidian**, **micro**.
- [x] **Style config links in repo:** symlink hub created at `themes/links/` for active style files (`kitty`, `Cursor`, `Obsidian`, `micro`, `Kvantum`).
- [ ] **Strategy** — [04 — Plasma first, then Stylix](./04-ricing.md#strategy--plasma-first-then-stylix): decide whether to keep this manual pass or formalize in **Plasma-only** + later **Stylix**.
- [ ] **Investigation** — [04 — Theseus / Plasma 6](./04-ricing.md#investigation--theseus-plasma-6--wayland--framework-13) + [checklist](./04-ricing.md#checklist--investigation-in-progress) (parallel with [hotkeys](./02-functional-improvements.md#wm--hotkey-notes)).
- [ ] **Polish “done”** — [04 — Done when](./04-ricing.md#done-when); **keyboard backlight at night** and optional **sunset / night-mode** sync ([04 — Framework display](./04-ricing.md#framework-display)).

---

## Quick reference

| Decision | Where |
|----------|--------|
| All locked choices | [LOCKED.md](./LOCKED.md) |
| Package restore order | [05](./05-previous-nixos-config-extract.md) + [Q8](./00-audit-priorities-and-risks.md#q8-package-restore-priority) |

**Current step:** **C + E follow-through** — finalize **[Hotkeys](./02-functional-improvements.md#wm--hotkey-notes)** and decide whether to codify current theming in [04](./04-ricing.md) (**Plasma-only first / Stylix later**). **`outside`:** [deferred](./08-dotfiles-migration-plan.md#deferred--later). **No Phase D HM user-config migration** until you work [§ D](./06-implementation-checklist.md#d--home-manager-phase-d-migration-deferred) (scaffold is separate). **Deferred:** suspend **drain / `deep`**, **captive/hotel** VPN retest — [02 — Low-power](./02-functional-improvements.md#low-power-suspend-investigation), [FrootVPN + Stunnel](./02-functional-improvements.md#frootvpn--stunnel--vortix-theseus).

# Audit — priorities, phases, risks, open questions

**Plan lock:** Decisions **Q1–Q10** are **frozen** — summary table in [LOCKED.md](./LOCKED.md) (2026-04-05).

This document **audits** the roadmap files (`01`–`05`), **orders work by value vs complexity**, **sequences phases** for execution, and lists **risks** and **decisions** captured before implementation.

---

## 1. Snapshot of the current plan

| Artifact | Role |
|----------|------|
| [01-baseline-nix-packages.md](./01-baseline-nix-packages.md) | Nix mental model, search/rebuild tooling, config location (`-I`, flake), rebuild script, optional Framework firmware notes |
| [02-functional-improvements.md](./02-functional-improvements.md) | Kitty, zsh, chezmoi porting hints, **tiling WM + focus-follows-mouse + hotkeys**, hardware/network/audio/print, Framework ergonomics |
| [03-home-manager.md](./03-home-manager.md) | Home Manager install path, **chezmoi vs HM** boundaries, `programs.kitty` / zsh / git / session env |
| [04-ricing.md](./04-ricing.md) | Fonts, themes, bar/launcher/notifications, polish |
| [05-previous-nixos-config-extract.md](./05-previous-nixos-config-extract.md) | What transfers from old machine vs not; package shopping list; Plasma vs tiling warning |

**Gap:** Phase 2 is **dense**. It mixes *infrastructure*, *desktop stack*, *WM behavior*, and *user shell* — fine as one phase file, but **order inside Phase 2** matters (see §4).

---

## 2. Value × complexity (prioritize what to do first)

Rough scale: **value** = impact on daily use; **complexity** = time, foot-guns, integration surface.

### High value, low complexity (do early)

- Regenerate **`hardware-configuration.nix`** for the Framework; set **`system.stateVersion`** for *this* install.
- **NetworkManager**, **PipeWire**, **Bluetooth**, **printing**, **polkit**, **libinput**, locale/timezone — mostly declarative toggles ([05](./05-previous-nixos-config-extract.md)).
- **Rollback path**: boot previous generation + `nixos-rebuild list-generations` (Phase 1).
- **Baseline search**: stock `nix search` / `nix repl` until you need more.

### High value, medium complexity (core of “usable system”)

- **Display stack**: Wayland vs X11, display manager or TTY+WM — **must align** with tiling choice.
- **Tiling WM** + **focus-follows-mouse** + **hotkey map** — high touch, but bounded to one compositor’s docs.
- **Kitty** as default terminal everywhere (`$TERMINAL`, bindings, `.desktop` / portal behavior).
- **zsh** + essential plugins (syntax highlighting, autosuggestions, completions) — whether via **system `programs.zsh`** first or straight to **Home Manager** is an open choice (§5).
- **`nix-search-cli`** and/or your **rebuild script** (you already know this pattern; paths may change).

### High value, high complexity (schedule after basics work)

- **Home Manager + chezmoi** with a clear **ownership map** — easy to get double-writes or drift ([03](./03-home-manager.md)).
- **Flake-first** config vs **classic** + `-I nixos-config=…` — switching later is doable but has migration cost.
- **Full** package restore from [05](./05-previous-nixos-config-extract.md) — better **incremental** than one huge rebuild.
- **Oh-my-zsh parity** vs **slimmer HM-native zsh** — reproducing old *behavior* without copying every plugin blindly.

### Medium value, medium complexity (defer until core is stable)

- **`nixos-cli`** — helpful; not blocking if `nix`/`nixos-rebuild` are enough.
- **Steam** + firewall knobs, **Discord/Obsidian**-class apps — need **`allowUnfree`**, larger closures, more updates.

### Lower priority until function is solid

- Full **rice** (Phase 4): bar, launcher, wallpaper pipeline, theme unification — high satisfaction, but depends on WM/stack choices.

---

## 3. Recommended execution order (phases, refined)

Keep the **four phase files** as the narrative spine, but use this **internal sequence** so you are not debugging WM + chezmoi + HM at once.

### Phase A — Bootstrap (maps to **01** + start of **05**)

1. Hardware + `stateVersion` + hostname + user/groups.
2. Decide **where config lives** (flake vs `-I` vs import from `~`) and document it in Notes.
3. Comfort with **search**, **rebuild**, **rollback**; optional **rebuild script** + **`nix-search-cli`**.
4. Skim **Framework** docs for firmware/kernel gotchas (carry issues into Phase B).

### Phase B — Base system (subset of **02** + **05** table)

1. NetworkManager, PipeWire, Bluetooth, printing, locale, keyboard layout (X + Wayland as needed).
2. **Suspend**, **brightness**, **camera**, **dock** — validate before living in WM tweaks.
3. **Browser** (e.g. `programs.firefox.enable`) so you have docs while tuning WM.

### Phase C — Interactive session (rest of **02** WM + terminal)

1. Install and log into **tiling stack** (compositor + session + DM/greetd as required).
2. **Focus-follows-mouse** + **tiling** + **hotkeys** + written binding table.
3. **Kitty** + **zsh** + minimal plugins; **default terminal** wired correctly.
4. **Chezmoi**: add **NixOS template conditions** and port **aliases/snippets** — *light* touch; full HM migration can wait until Phase D.

### Phase D — User config consolidation (**03**)

1. Choose **standalone HM** vs **NixOS HM module**.
2. Move **Kitty**, **zsh**, **git**, **session env** into HM where appropriate; resolve **chezmoi vs `home.file`** for each path.
3. Secrets hygiene when you add tokens.

### Phase E — Polish (**04** + tail of **05**)

1. Fonts, GTK/Qt, icons, bar/launcher/notifications, wallpaper.
2. Revisit **Nerdfonts** / icon themes from old config; avoid heavy blur if battery matters.

**05** is read **throughout** B–E as a checklist, not a phase by itself.

---

## 4. Risks

| Risk | Mitigation |
|------|------------|
| **Chezmoi and Home Manager both manage the same file** | Maintain a **path inventory**: each dotfile has exactly one owner; use `home-manager`’s `xdg.configFile` *or* chezmoi, not both for the same target. |
| **Phase 2 tries to change WM + zsh + HM + chezmoi in one week** | Follow §3 order: **B → C session → D HM**; only **light** chezmoi during C if needed. |
| **Stack mismatch** (DE + second full compositor) | [05](./05-previous-nixos-config-extract.md) flags this; on **Theseus** **Plasma + tiling** is the single path — do not add a second full compositor (e.g. Sway) without a reason. |
| **Rebuild script commits on success** | Ensure commits only when **you** want history; add **`nixos-switch.log`** to `.gitignore` if noisy; review **error handling** so failed builds do not commit. |
| **Unfree + Steam + large games** | Bigger store, slower rebuilds; enable **`allowUnfree`** only when needed; add Steam in a **dedicated** change for easy rollback. |
| **Focus-follows-mouse + games / fullscreen** | Some games grab pointer; document **exceptions** or toggles in WM notes. |
| **Flake lock vs channel drift** | Pin **one** `nixpkgs` story; document update cadence (`nix flake update` vs channel). |

---

## 5. Questions and decisions (locked)

All items below are **decided** — see [LOCKED.md](./LOCKED.md). The numbered list is kept as **context**; the **decisions log** table is authoritative.

1. **Compositor / WM:** **Locked:** **KDE Plasma (Wayland) + tiling** — not Sway/Hypr for this machine. (Old config had commented Hyprland/Sway; historical only.)
2. **Wayland vs X11** as primary? (Affects focus-follows-mouse options, screen sharing, some games.)
3. **Nix config style:** **flake** (`nixos-rebuild --flake …`) vs **classic** + `-I nixos-config=…` — which is canonical for this machine? *(See [Q3 discussion](#q3-flake-vs-classic) below.)*
4. **Home Manager integration:** **standalone** (`home-manager switch`) vs **NixOS module** (single `nixos-rebuild` for system + user)?
5. **Chezmoi strategy:** (a) chezmoi generates files HM does not touch, (b) migrate templates into HM, or (c) hybrid with an explicit list — **which default?** *(See [§Q5](#q5-chezmoi-vs-home-manager).)*
6. **zsh story:** Replicate **oh-my-zsh** (old config) vs **HM `programs.zsh`** plugins only vs **chezmoi-driven `.zshrc`**? *(See [§Q6](#q6-zsh-story).)*
7. **Username and hostname** on the Framework — same as `wiz` / `nixos` or new? *(See [§Q7](#q7-username-and-hostname).)*
8. **Package restore priority** from [05](./05-previous-nixos-config-extract.md): dev toolchain first, or comms/productivity, or gaming? *(See [§Q8](#q8-package-restore-priority).)*
9. **`EDITOR`:** stay on **micro** (old habit) or standardize on **Neovim**/elsewhere in Phase 2? *(See [§Q9](#q9-editor).)*
10. **zram 25%** again or different swap story for Framework RAM profile? *(See [§Q10](#q10-zram-and-swap).)*

### Decisions log

| # | Topic | Decision | Notes |
|---|--------|----------|--------|
| 1 | Compositor / WM | **Plasma (Wayland) + tiling** | **Locked** daily driver; **Sway** / Hypr **not** targeted. |
| 2 | Wayland vs X11 | **Wayland primary** | **Plasma** session. **XWayland** on for **games and legacy X apps**. **Screen sharing:** **xdg-desktop-portal** + **KDE** portal on Plasma; **PipeWire** for capture; verify **browser / Discord / OBS** after setup. (**wlr** portal only if you add a wlroots-based session later.) |
| 3 | Flake vs classic `-I` | **Classic** | **`nixos-rebuild switch -I nixos-config=…`** (or minimal `/etc/nixos` import); **`nixpkgs` via channels**. **Flakes later** when you want pinned inputs — not required for Home Manager. |
| 4 | Home Manager: standalone vs module | **NixOS module** + minimal **`home.nix`** (scaffold) | Original learning path was **standalone** `home-manager switch` first; **live system** uses the **NixOS module** so **`nixos-rebuild`** applies system + HM together. **Phase D** (Kitty, zsh, git, etc. in HM) still **deferred** — see [LOCKED](./LOCKED.md). |
| 5 | Chezmoi strategy | **Hybrid (c)** — *confirmed* | **Chezmoi:** cross-distro templates ([debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main)), machine-specific data, secrets. **HM:** `programs.kitty`, `programs.zsh`, `programs.git`, `sessionVariables`, other `programs.*` where you want Nix options. **Rule:** [one owner per path](#q5-chezmoi-vs-home-manager); maintain an **ownership list** in git. |
| 6 | zsh story | **HM `programs.zsh` primary** — *confirmed approach* | **Syntax highlighting + autosuggestions + completions** in HM. **Oh-my-zsh** not required — use HM’s **`programs.zsh.ohMyZsh`** *only if* you want themes/plugins like the old box; otherwise stay slimmer. **Chezmoi:** optional **shared** snippets (e.g. aliases) via a **file HM sources** in `initExtra`, *or* aliases only in HM on Nix — [§Q6](#q6-zsh-story). |
| 7 | Username / hostname | **`wiz`** / **`Theseus`** — *confirmed* | `networking.hostName = "Theseus";` — **users.users.wiz** (or equivalent). |
| 8 | Package restore priority | **Dev → comms/productivity → gaming** — *confirmed order* | Restore **git, compilers, node, editors, build tools** first (easier debugging). Then **browser, chat, notes, VPN**. Then **Steam/games** + `allowUnfree` in a **separate** change — [§Q8](#q8-package-restore-priority). |
| 9 | `EDITOR` + editors | **`micro`** for terminal env — *confirmed* | **`EDITOR` / `VISUAL` / `SYSTEMD_EDITOR`** → **`micro`**. **Heavier work:** **VS Code** or **VSCodium**, **Cursor**. **Markdown preview:** **Glow** (`pkgs.glow`). — [§Q9](#q9-editor). |
| 10 | zram / swap | **Existing swap only — no zram** — *confirmed* | **Swap** already configured on this machine; **do not** enable **`zramSwap`** unless you change your mind. — [§Q10](#q10-zram-and-swap). |

### Q3: Flake vs classic

**Classic** (`configuration.nix` + `sudo nixos-rebuild switch -I nixos-config=/path/to/configuration.nix`):

- Matches your **existing rebuild script** pattern; small mental model; plenty of wiki/manual examples.
- **`nixpkgs` revision** comes from **channels** (`nix-channel`) or another pin — you should know **how** it updates (`sudo nix-channel --update`).
- **Home Manager** can be **standalone** (`home-manager switch`) or the **NixOS module** fed by the same `configuration.nix` — no flake required.

**Flake** (`flake.nix` + `sudo nixos-rebuild switch --flake /path/to/repo#hostname`):

- **`flake.lock`** pins **inputs** (`nixpkgs`, `home-manager`, `hardware`, etc.) — reproducible and explicit; `nix flake update` when you choose.
- **One** entry point for system (and often Home Manager as a module); common in **new** NixOS dotfile repos.
- Your **rebuild script** should call **`nixos-rebuild … --flake …`** instead of `-I nixos-config=…`; commit **`flake.lock`** with your config repo.

**Hybrid (valid but keep it clear):** e.g. flake for the machine but document that **one** command is canonical — avoid mixing `switch` styles without knowing which generation you are building.

**Recommendation (non-binding):** If you want **pinned inputs** and a single locked tree (good with **git** + multiple machines later), lean **flake**. If you want **least change** from your current script and are fine with **channels**, lean **classic** until you outgrow it.

**Recorded (Q3):** **Classic** first — learn **NixOS system config** and **`nix-channel` / `nixos-rebuild`** without flakes; add **flakes** when you explicitly want **`flake.lock`** and `--flake`. **Home Manager** next (see Q4): **standalone** keeps concerns separate while learning.

### Q5: Chezmoi vs Home Manager

You already use **[chezmoi](https://www.chezmoi.io/)** with **[debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main)** (Debian + Omarchy). On NixOS you will also use **Home Manager** (standalone first). Three strategies:

| Option | Meaning | Fits your case? |
|--------|---------|-----------------|
| **(a) Chezmoi-first** | Chezmoi **renders** almost all dotfiles; Home Manager only manages what chezmoi does **not** (or only system-level stuff outside HM). | Keeps **one** template story for three OSes; risk of **under-using** HM’s `programs.*` (duplicated logic in shell snippets). |
| **(b) Migrate to HM** | Move templates into **`home.nix`** / `home.file` / `xdg.configFile` and shrink chezmoi. | **Single** tool for Nix machines; **more work** up front; **Debian/Omarchy** either lose shared templates or need a **non-Nix** export path. |
| **(c) Hybrid + explicit ownership** | **Each path has exactly one owner.** Example split: HM for **`programs.kitty`**, **`programs.zsh`** (options/plugins), **`programs.git`**, **`sessionVariables`**; chezmoi for **editor configs**, **SSH/config** snippets, **`.local` scripts**, and **anything** still shared heavily across non-Nix OSes via templates. Maintain a **small list** (table in repo or Phase 3 notes). | **Practical default:** learn HM where it shines; keep chezmoi for **cross-distro** muscle memory and **per-machine** data. |

**Rules that prevent pain:**

- **Never** let chezmoi and HM write the **same file** (e.g. both touching `~/.config/kitty/kitty.conf` — pick one).
- After **`chezmoi apply`** and **`home-manager switch`**, the home directory should be **consistent**; if in doubt, **HM generates** the file and chezmoi **ignores** that path (`.chezmoiignore`).
- **Order of operations** (typical): `chezmoi apply` then `home-manager switch`, or only HM on Nix if that path is HM-owned — **document** which you use.

**Recorded (Q5):** **(c) Hybrid** — **confirmed.** Keep an **ownership list** in git; revisit **(b)** later on Nix-only machines if chezmoi shrinks to almost nothing.

### Q6: zsh story

Your old NixOS config used **system `programs.zsh`** + **oh-my-zsh** (theme `jonathan`, several plugins). With **Q5 hybrid**, zsh on this machine should be:

| Approach | Verdict |
|----------|---------|
| **Full oh-my-zsh** (system or heavy script) | **Optional.** HM can enable **`programs.zsh.ohMyZsh`** if you want the same *kind* of setup without losing reproducibility. |
| **HM `programs.zsh` “native”** | **Default path:** `autosuggestion.enable`, `syntaxHighlighting.enable`, completions, `shellAliases` / `initExtra` as needed — matches Phase 2 “essential plugins.” |
| **Chezmoi-only `.zshrc`** | **Avoid** as the *only* story on Nix if HM also manages zsh — **conflicts** with [one owner per path](#q5-chezmoi-vs-home-manager). **Allowed:** chezmoi deploys a **file you source** from HM `initExtra` (e.g. shared aliases for Debian + Nix), or **chezmoi ignores** `~/.zshrc` on the NixOS profile. |

**Recorded (Q6):** **Home Manager leads** for zsh on NixOS; **oh-my-zsh via HM** only if you miss it; **chezmoi** only for **non-overlapping** shared snippets or **ignored** paths.

### Q7: Username and hostname

- **Username:** **`wiz`**
- **Hostname:** **`Theseus`** — set `networking.hostName = "Theseus";` in `configuration.nix` (or equivalent).

### Q8: Package restore priority

Order when pulling packages from [05-previous-nixos-config-extract.md](./05-previous-nixos-config-extract.md):

1. **Dev / CLI** — `git`, `gcc`, `gnumake`, `nodejs`, editors, `fzf`, `tmux`, etc. (bisect-friendly).
2. **Comms / productivity** — browser, Discord, Obsidian, VPN, Bitwarden, LibreOffice as needed.
3. **Gaming** — Steam, `allowUnfree`, firewall options — **separate** commit/rebuild so rollback is easy.

### Q9: EDITOR and editing tools

- **`micro`** for **`EDITOR`**, **`VISUAL`**, and **`SYSTEMD_EDITOR`** (terminal-first quick edits).
- **Heavier editing:** **VS Code** or **VSCodium**, and **Cursor** — add to `environment.systemPackages` / Home Manager when you declare them (watch **unfree**/license for Cursor if using nixpkgs wrappers).
- **Markdown in the terminal:** **Glow** (`pkgs.glow`) for comfortable `.md` reading.

### Q10: zram and swap

**Do not enable `zramSwap`** on this install — **swap is already set up** and you do not want extra zram on top. If you ever **resize** swap or add **hibernate**, adjust **disk swap** only; revisit zram only if your requirements change.

---

## 6. Plan health (brief)

- **Strengths:** Clear separation of baseline vs function vs HM vs rice; honest **previous config** extract; **focus-follows-mouse** and **Kitty** called out; **risks** around chezmoi/HM are documented in Phase 3.
- **Watch:** Phase 2 **done when** is ambitious (full workday + WM + kitty + zsh); acceptable as a **north star**, but expect **milestones** (e.g. “network + audio + WM login” first).

### Status addendum (2026-04-08)

- **Session theming baseline is now implemented across apps** (manual pass): **Kvantum (LilacAsh)**, **Kitty**, **Cursor** (workbench + terminal ANSI), **Obsidian** (`LilacAsh` theme), and **micro** (`LilacAsh.micro`).
- **Font alignment is in place** for that styling pass: **`IosevkaTermSlab NFM`** used in Kitty/Cursor/Obsidian theme variables.
- **Config discoverability improved:** symlink hub created at `~/Stellarium/themes/links/` pointing to active style configs in `~/.config` and Obsidian vault theme files.
- This materially reduces risk for **Phase E consistency drift** (single palette + linked config paths), while **D (Home Manager ownership)** remains deferred by design.

---

## Notes (fill in as you decide)

- **Q3–Q4 (2026):** Classic NixOS + channels first; **standalone Home Manager** when ready to learn user-level config; **flakes** and **HM NixOS module** deferred until useful.
- **Q5 (confirmed):** **Hybrid (c)** — chezmoi + HM, **one owner per path**, ownership list in git; see §Q5.
- **Q6–Q10:** **HM-first zsh**; **user `wiz`**, **host `Theseus`**; **package order** dev → productivity → gaming; **`micro`** + **VS Code/VSCodium/Cursor** + **Glow**; **swap already present — no zram** — see §Q6–§Q10.
- **2026-04-08 status:** LilacAsh color rollout + font alignment completed for current app set (Kvantum/Kitty/Cursor/Obsidian/micro); style symlinks available in `themes/links` for quick audit/edit.

# Dotfiles migration plan (Theseus / NixOS + Plasma)

**Related:** [LOCKED — Dotfiles strategy](./LOCKED.md#execution-note-rolling), [02 — Chezmoi bootstrap](./02-functional-improvements.md#chezmoi-bootstrap-then-nixos-migration), [06 — § C](./06-implementation-checklist.md#c--session-kitty-shell-wm).

**Principle:** **One owner per path.** Prefer **`~/.config/nixos/configuration.nix`** for machine policy; edit **`~/.config/...`** directly for ad hoc dotfiles (**moving off chezmoi**). If anything remains in chezmoi temporarily, use **`.chezmoiignore`** when Nix or XDG owns a file.

**Order of work:** GTK removal, WM stack removal, **`dot_bash_aliases` / zsh alias merge**, Newsboat path, and Nix **`shellAliases`** are done for the current wave. **Outside** — install **`outside`** via **`cargo install outside`** when you want it ([§ Deferred / later](#deferred--later)); config stays at **`~/.config/outside/config.yaml`** (see chezmoi **`dot_config/outside/`** or copy into **`~/.config`**).

### Home directory cleanup (done on Theseus, 2026-04)

- **Archived** leftover **`~/.config/hypr/`** (no longer managed after WM stack removal) to **`~/dotfiles-archive/2026-04-05-orphans/hypr/`**.
- **Newsboat:** feeds live under **`~/.config/newsboat/urls`** (XDG); legacy **`~/.newsboat/`** moved to **`~/dotfiles-archive/2026-04-05-orphans/newsboat-dotdir/`**. See **`~/dotfiles-archive/2026-04-05-orphans/README.txt`**.
- **Fastfetch** is edited only in **`~/.config/fastfetch/config.jsonc`** (not chezmoi); migrate to Home Manager later ([03](./03-home-manager.md)).

---

## Default terminal (Kitty) — verification

| Check | Status |
|-------|--------|
| **Kitty** in **`environment.systemPackages`** | Yes. |
| **`TERMINAL`** | **`environment.sessionVariables.TERMINAL`** → **`${pkgs.kitty}/bin/kitty`**. |
| **Chezmoi data** | **`terminal = "kitty"`**, **`has_omarchy = false`**. |
| **Plasma shortcut** | Optional: bind **Launch terminal** to Kitty if it still opens Konsole. |

---

## Decisions (rolling)

### GTK

- **Policy:** Use **Plasma** for GTK/Qt theming and settings.
- **Action:** **Removed** chezmoi **`dot_config/private_gtk-3.0/settings.ini`**. Delete **`~/.config/gtk-3.0/settings.ini`** on disk if still present after Plasma-only use.
- **NixOS:** No extra GTK block required unless you later pin themes declaratively.

### `~/.local/bin` scripts — address **each**

| Chezmoi path | Notes |
|--------------|--------|
| **`executable_search`** | Review purpose; keep in chezmoi, or **`pkgs.writeShellApplication`** + **`systemPackages`**. |
| **`executable_afk`** | Same. |
| **`executable_launch-rofi`** | **Removed** with Rofi stack. |
| **`executable_rofi-bookmarks.py`** | **Removed** with Rofi. |
| **`executable_rofi-google`** | **Removed** with Rofi. |
| **`executable_hypridle-status.sh`** | **Removed** with Hypridle. |
| **`hypridle-checks/*`** | **Removed** with Hypridle. |

After removals, **re-decide** whether **`~/.local/bin`** stays chezmoi-managed or moves entirely into Nix.

### `logon.sh`

- **Removed** from chezmoi (**`logon.sh`**, **`dot_config/executable_logon.sh`**). **`logon`**, **`logonconfig`**, **`swayconfig`** aliases removed (were tied to deleted paths).

### Sway, Hyprland, Rofi, Wezterm, Waybar, Wofi, Hypridle-related paths

- **Removed** from chezmoi source, including:
  - **`dot_config/sway/`**
  - **`dot_config/hypr/`** (configs + shaders)
  - **`dot_config/rofi/`**
  - **`dot_config/wezterm/`**, top-level **`wezterm/`**
  - **`dot_config/waybar/`**
  - **`wofi.css`** (Wofi dropped entirely)
  - **`dot_local/bin`** entries tied to **rofi** / **hypridle** (table above)

### Reference only (do **not** delete yet)

| Item | Notes |
|------|--------|
| **`dot_config/logon-tmux/`** | Kept in chezmoi for reference. |
| **`dot_config/systemd/user/tmux-startup.service`** | Kept for reference; enable with **`systemctl --user enable`** if you want tmux at graphical login. |

### Newsboat + Outside

| Item | Action |
|------|--------|
| **Newsboat** | **`pkgs.newsboat`** in **`environment.systemPackages`**. Feeds: **`dot_config/newsboat/urls`** → **`~/.config/newsboat/urls`** (XDG). Old **`private_dot_newsboat/`** removed from chezmoi after migration. |
| **outside** | **Deferred** — not in **`nixpkgs`**; install later via **`cargo install outside`** ([trmn.sh](https://www.trmn.sh/tools/outside), [GitHub](https://github.com/BaconIsAVeg/outside)). Keep **`~/.config/outside/config.yaml`**; align **`outside.desktop`** **`Exec=`** once **`outside`** is on **`PATH`**. |

### Deferred / later

- [ ] **`outside` (weather CLI)** — **`cargo install outside`** (or package with **`buildRustPackage`** later). Refs: [trmn.sh — outside](https://www.trmn.sh/tools/outside), [BaconIsAVeg/outside](https://github.com/BaconIsAVeg/outside).

### Bash: **`dot_bash_aliases`** + zsh aliases → Nix

- **Done:** **`dot_bash_aliases`** and **`dot_bashrc.tmpl`** **removed** from chezmoi; aliases merged into **`programs.zsh.shellAliases`** in **`configuration.nix`** (see comment block there).
- **Conflict rules:** Values are **strings**; Nix uses **`escapeShellArg`** for alias values.
- **`dot_zshrc`:** Duplicate **`alias`** lines **stripped**; pointer comment to Nix.
- **Stale path aliases (explicit):** After removing templates, **delete or replace** aliases that pointed at removed paths — e.g. **`swayconfig`**, **`logonconfig`**, **`logon`** — so the shell does not reference missing files (**item 6**).

### Tricky aliases (**item 7**)

- **Policy:** Treat **`keyboard-flash`**, AppImage **`obsidian`/`gimp`**, **`agent`***`, etc. as **one-at-a-time** when something breaks — adjust in **`configuration.nix`** or move to **`interactiveShellInit`** only if **`shellAliases`** quoting is insufficient.

---

## Process checklist (don’t skip)

1. **Edit chezmoi source** in **`~/.local/share/chezmoi/`** — delete templates, add **`newsboat`** paths as decided.
2. **`git status`** / commit in **dotfiles** repo.
3. **`chezmoi apply`** — confirm no errors; **`chezmoi unmanaged`** to see stray files under **`$HOME`** if needed.
4. **Remove orphaned home files** that chezmoi no longer manages (e.g. old **`~/.config/hypr`**, **`~/.newsboat`** if you moved to XDG-only): **backup first**, then **`rm -rf`** or move aside.
5. **`~/.config/nixos/configuration.nix`** — **`newsboat`**, **`shellAliases`**, etc.; **`outside`** only when you do [§ Deferred / later](#deferred--later).
6. **`sudo nixos-rebuild switch`**.
7. **New shell / re-login** for **`TERMINAL`**, **`shellAliases`**, **`sessionVariables`**.
8. **Stellarium / docs** — tick **[WM / hotkey table](./02-functional-improvements.md#wm--hotkey-notes)** when done; update this file if decisions change.

---

## Gaps — resolved / remaining

| Item | Decision |
|------|----------|
| **Waybar** | **Deleted** with tiling WM stack (not used on Plasma here). |
| **`wofi.css`** | **Dropped** (Wofi not used). |
| **`dot_bashrc.tmpl`** | **Dropped** (zsh is default shell; aliases live in Nix). |
| **`dot_config/systemd/user/tmux-startup.service`** | **Kept for reference** (see table above). |
| **`dot_config/logon-tmux/`** | **Kept for reference**. |
| **Top-level `wezterm/`** vs **`dot_config/wezterm/`** | **Removed** (Kitty is default terminal). |
| **`.desktop` files** | **`dot_local/share/private_applications/*`** — review **Exec=** after deleting tools (e.g. Rofi); do when touching each app. |
| **Kitty** | Still chezmoi **`kitty.conf.tmpl`** — OK until you move to **`programs.kitty`**. |

---

## Home Manager

**Live `~/.config/nixos`:** User config is already in **Home Manager** under **[`./home/`](../../home/)** (see [03 — Home Manager](./03-home-manager.md), [LOCKED — live repo note](./LOCKED.md#live-repo-note-2026-04), [MIGRATION.md](../../MIGRATION.md)). On other machines or fresh experiments, you can still use standalone **`home-manager switch`** with `~/.config/home-manager/home.nix` if you want a separate workflow.

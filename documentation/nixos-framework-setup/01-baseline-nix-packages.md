# Phase 1 — Baseline: search, evaluate, and install packages

**Goal:** Before changing the system heavily, get comfortable with **how NixOS exposes software** and how you’ll add it to config reproducibly.

**Plan context:** [LOCKED.md](./LOCKED.md) — **classic** NixOS (`nixos-rebuild` + channels / `NIX_PATH`), **not flakes** for now. **Hostname `Theseus`** (`networking.hostName = "Theseus"`), user **`wiz`**.

If **`configuration.nix`** is under **`~/.config/nixos/`** instead of **`/etc/nixos`**, pass **`nixos-config`** explicitly: **`nixos-rebuild … -I nixos-config=/path/to/configuration.nix`** or **`NIXOS_CONFIG=/path/to/configuration.nix nixos-rebuild …`**. A bare **`-I /path/...`** (without **`nixos-config=`**) causes `file 'nixos-config' was not found in the Nix search path`.

## Begin Phase 1 (do this first)

1. **Confirm classic layout** — You have `/etc/nixos/configuration.nix` (and `hardware-configuration.nix`). `NIX_PATH` should include `nixos-config=…` and a `nixpkgs` channel path. No `flake.nix` required.
2. **Enable modern `nix` CLI features** — `nix search nixpkgs …` resolves **`nixpkgs`** via the **flake registry**, so Nix needs **both** **`nix-command`** and **`flakes`** experimental features. That only enables **CLI** behavior; your system can stay **classic** (`/etc/nixos/configuration.nix`, no `flake.nix`) — [LOCKED](./LOCKED.md) is about **OS config style**, not this toggle. Add to `configuration.nix`:
   ```nix
   nix.settings.experimental-features = [ "nix-command" "flakes" ];
   ```
   Then: `sudo nixos-rebuild switch`
3. **Try discovery:**
   - `nix search nixpkgs firefox` (after step 2)
   - `nix repl -f '<nixpkgs>'` — then type `pkgs.` and Tab, or `pkgs.firefox.meta.description`
4. **Practice rollback muscle memory:** `sudo nixos-rebuild list-generations` — know how to pick **previous generation** at boot if a switch goes wrong.
5. **Optional:** install **`nix-search-cli`** or **`alejandra`** via `environment.systemPackages` when you are ready (see below).
6. **Notes:** Write your real **`-I nixos-config=…`** path (or import layout) and **which** search command you use in the [Notes](#notes) section at the bottom of this file.

## Mental model (check when it clicks)

- [ ] **Channels vs flakes:** You are on **classic** **system** config ([LOCKED](./LOCKED.md)); **`nixpkgs`** comes from **channels** / `NIX_PATH`. Enabling **`flakes`** in `nix.settings.experimental-features` only unlocks **CLI** commands like `nix search` — a **`flake.nix` for the OS** is still optional later.
- [ ] **System vs user:** You know the difference between **system packages** (`environment.systemPackages` in `configuration.nix`) and **user/profile** installs (`nix profile`, Home Manager, dev shells).
- [X] **Option vs package:** You know that some things are **NixOS modules** (options like `services.*`, `programs.*`) vs plain packages in `environment.systemPackages`.

## Stronger baseline tooling (pick one, combine, or a script)

Stock **`nix search`** / **`nix repl`** are enough to start. The plan also mentioned **community** CLIs — here is how they relate to each other and to **classic** NixOS.

| Tool | Role | How to use it on NixOS |
|------|------|-------------------------|
| **`nix search`**, **`nix repl`** | Core discovery (`nix search nixpkgs …`, explore `pkgs` in a repl) | Requires **`nix-command`** + **`flakes`** in **`nix.settings.experimental-features`** ([Begin Phase 1](#begin-phase-1-do-this-first)). **Does not** require a `flake.nix` for your machine. |
| **[nix-search-cli](https://github.com/peterldowns/nix-search-cli)** | Terminal search against **`search.nixos.org`**; binary **`nix-search`** | In **`configuration.nix`:** `environment.systemPackages = with pkgs; [ nix-search-cli ];` — then `nix-search firefox` (see upstream for flags). |
| **[nixos-cli](https://github.com/nix-community/nixos-cli)** | All-in-one NixOS helper (generations TUIs, wrappers around rebuild, etc.) | **Not** always in **`nixpkgs`** on a given channel. **Try without installing:** `nix run github:nix-community/nixos-cli -- --help` (same **`nix-command` + `flakes`** prerequisite). For a **declarative** install, check whether your **`nixpkgs`** revision includes **`nixos-cli`**, or use an **overlay** / follow [upstream](https://nix-community.github.io/nixos-cli). |
| **`os-rebuild` (this repo)** | Guided: edit → format → diff → **`nixos-rebuild`** → commit → notify | See below — installs to `/usr/local/bin/os-rebuild`; targets classic with `-I nixos-config=…`. |

**Practical combo:** **`nix search`** or **`nix-search`** for finding packages + your **rebuild script** for day-to-day switches. Add **`nixos-cli`** when you want its TUIs / unified UX — it is optional.

**Shell alias `ns`:** If you use **`nix-search-cli`**, add **`ns = "nix-search"`** to **`programs.zsh.shellAliases`** (system or Home Manager). Example fragment: [snippets/zsh-ns-alias.nix](./snippets/zsh-ns-alias.nix). Then **`ns firefox`** runs **`nix-search firefox`** (open a **new zsh** session after **`nixos-rebuild switch`**).

**Still seeing bash?** Check **`getent passwd wiz`** — if the shell is **zsh** but **`echo $SHELL`** is **bash**, your **desktop session** (e.g. Plasma) may still export **`SHELL=bash`**. Add **`environment.variables.SHELL = "${pkgs.zsh}/bin/zsh";`** (see snippet), **`sudo nixos-rebuild switch`**, then **log out of the desktop** (or **reboot**) so Konsole/Kitty pick up **zsh**.

Checklist:

- [X] **Stock `nix` CLI** — `nix-command` + `flakes` enabled; **`nix search`** and **`nix repl`** work.
- [X] **`nix-search-cli`** — added to **`environment.systemPackages`** if you want **`nix-search`** in addition to **`nix search`**.
- [X] **`nixos-cli`** — tried with **`nix run github:nix-community/nixos-cli`** or installed if available in your **`nixpkgs`**.
- [X] **Rebuild script** — saved, executable, paths match your **`nixos-config`** (see below).

## Where the system config lives (choose consciously)

Several valid patterns; pick one and document it in Notes:

1. **Minimal `/etc/nixos/configuration.nix`** that only **imports** your real config from somewhere under `$HOME` (e.g. `~/.config/nixos/`).
2. **Symlink** `/etc/nixos/configuration.nix` → file in home — can make **relative paths** awkward; some people avoid this.
3. **No import trick:** point `nixos-rebuild` at your file with  
   `nixos-rebuild switch -I nixos-config=/path/to/configuration.nix`  
   so the canonical config can live entirely in dotfiles with **no** extra bootstrap beyond what `/etc/nixos` already needs (if anything).
4. **Flake-first:** `nixos-rebuild switch --flake /path/to/flake#hostname` — **deferred** until you outgrow classic ([LOCKED](./LOCKED.md)).

Other patterns may fit better later (e.g. deploy tools); update this list if you settle on something else.

## CLI: find and inspect

- [X] **`nix search`** — search via flake registry; requires **`nix-command`** and **`flakes`** in `nix.settings.experimental-features` (see [Begin Phase 1](#begin-phase-1-do-this-first)). Does **not** require a `flake.nix` for your system.  
  Example: `nix search nixpkgs firefox`
- [X] **`nix repl -f '<nixpkgs>'`** — explore `pkgs.*` and attrpaths interactively (works without flakes; see [Begin Phase 1](#begin-phase-1-do-this-first)).
- [ ] **Read package metadata** — note **license**, **platforms**, and **description** before adopting something critical.

## Installing (pick your workflow and practice once)

- [X] **Declarative (preferred on NixOS):** Add to `configuration.nix` (or Home Manager), then `sudo nixos-rebuild switch` (or `home-manager switch`).
- [X] **Ad hoc try:** Use **`nix shell nixpkgs#<attr>`** (flakes) or **`nix-shell -p <pkg>`** (non-flake) to test without committing to config.
- [X] **Rollback comfort:** Know how to list and boot a **previous generation** if a rebuild breaks something (boot menu / `nixos-rebuild` history).

## Rebuild helper: `os-rebuild` (guided UX)

Use the repository-provided helper for a clean, safe flow. It opens your editor with `sudo -E`, optionally formats with **alejandra**, shows diffs, runs `nixos-rebuild` with `-I nixos-config=…`, saves logs, optionally commits on success, and desktop-notifies.

Install:

```bash
sudo install -m 0755 ./os-rebuild.sh /usr/local/bin/os-rebuild
```

Defaults (override via env):

```bash
# Required: set your editor in your shell profile
export EDITOR=vim  # or micro, nano, etc.

# Optional overrides
export NIXOS_CONFIG="$HOME/.config/nixos/configuration.nix"
export NIXOS_DIR="$(dirname "$NIXOS_CONFIG")"
export OS_REBUILD_LOG_DIR="$HOME/.cache/os-rebuild"
```

Run:

```bash
os-rebuild
```

The script will prompt before formatting and rebuilding, show diffs (git-based if your config dir is a repo), and surface logs nicely on failure.

## Rebuild helper script (example — paths and tools yours to adjust)

This pattern: open editor → `cd` to config repo → **skip** if no `.nix` diff → **alejandra** → show diff → **rebuild** with `-I nixos-config=…` → log errors → **commit** with generation text → **notify-send**.

Dependencies to have on PATH: `git`, `alejandra`, `notify-send` (libnotify), `$EDITOR`. Uses a git repo at `~/.config/nixos` (change if yours differs).

```bash
#!/usr/bin/env bash
#
# Rebuild script: edit config, format, rebuild, commit on success, notify.
# Config layout notes (see "Where the system config lives" above):
#   - Minimal /etc/nixos importing home config, symlinks, -I nixos-config=..., or flake --flake.

set -e

$EDITOR ~/.config/nixos/configuration.nix

pushd ~/.config/nixos

if git diff --quiet '*.nix'; then
    echo "No changes detected, exiting."
    popd
    exit 0
fi

alejandra . &>/dev/null \
  || ( alejandra . ; echo "formatting failed!" && exit 1)

git diff -U0 '*.nix'

echo "NixOS Rebuilding..."

sudo nixos-rebuild switch -I nixos-config=/home/wiz/.config/nixos/configuration.nix &>nixos-switch.log \
  || (cat nixos-switch.log | grep --color error && exit 1)

current=$(nixos-rebuild list-generations | grep current)

git commit -am "$current"

popd

notify-send -e "NixOS Rebuilt OK!" --icon=software-update-available
```

**Polish ideas (optional):** configurable `NIXOS_CONFIG` / `CONFIG_DIR`; trap to `popd` on error; make grep step only surface stderr from nixos-rebuild without hiding success; pin `nixos-switch.log` in `.gitignore` if you do not want logs in the repo.

**On Theseus:** canonical config is **`/etc/nixos/configuration.nix`** (classic layout, no `-I` needed for a normal `nixos-rebuild switch`). For the same workflow with logging, formatting, and optional git commit, use the **single** helper at **[`os-rebuild.sh`](./os-rebuild.sh)** in this directory (or Stellarium `scripts/os-rebuild.sh` if your checkout includes it) — install as `os-rebuild`; set **`NIXOS_CONFIG=/etc/nixos/configuration.nix`** if that is your file. Use the longer **git + alejandra** block above only if you want a **literal inline** example; behavior-wise **`os-rebuild`** supersedes it.

## Framework-specific baseline (optional but useful early)

- [X] Confirm **firmware** / **kernel** situation matches Framework docs (generation, Intel vs AMD if appicable).
- [ ] Note any **hardware keys** (brightness, suspend) that need extra modules or udev — track in Phase 2 if issues appear.

## Done when

- [x] You can **find** a package, **decide** system vs user vs module, and **apply** it declaratively with a successful rebuild.
- [x] You have chosen **baseline tooling** — **`nix-search-cli`** + **`ns`** alias; stock **`nix search`** / **`nix repl`**; **`nixos-cli`** optional later.
- [x] **Personal cheat sheet** — see [Notes](#notes) below (Phase 1a, 2026-04).

## Notes

**Phase 1 (a) — cheat sheet (Theseus / wiz, classic NixOS)**

| Topic | What you use |
|--------|----------------|
| **Host / user** | **`Theseus`**, user **`wiz`**, shell **zsh** |
| **Config** | **`/etc/nixos/configuration.nix`** + **`./hardware-configuration.nix`**, **no** `flake.nix` |
| **Rebuild** | `sudo nixos-rebuild switch` (default **`nixos-config`** is `/etc/nixos/configuration.nix`) |
| **Generations** | `nixos-rebuild list-generations` — previous generation from **boot menu** if needed |
| **Nix CLI** | `nix.settings.experimental-features = [ "nix-command" "flakes" ];` — **CLI only**; OS stays classic ([LOCKED](./LOCKED.md)) |
| **Search** | `nix search nixpkgs <term>` and/or **`ns <term>`** → **`nix-search`** |
| **Repl** | `nix repl -f '<nixpkgs>'` |
| **SHELL** | **`environment.variables`** + **`sessionVariables`** + **`~/.config/environment.d/99-zsh-shell.conf`** so **`$SHELL`** is zsh under Plasma |

**Rebuild helper (single copy in this project folder):** [`os-rebuild.sh`](./os-rebuild.sh) — install to **`/usr/local/bin/os-rebuild`** (see [Rebuild helper: `os-rebuild`](#rebuild-helper-os-rebuild-guided-ux) above). For **`/etc/nixos`** only, set **`NIXOS_CONFIG=/etc/nixos/configuration.nix`**.

### Config repo git (`NIXOS_DIR`)

The **`os-rebuild`** script looks for a **git repository** at **`NIXOS_DIR`** (default: directory containing **`NIXOS_CONFIG`**, usually **`~/.config/nixos`**). That repo is **not** Stellarium: it is your **system config** backup. Give it a valid **remote** and push when you want an off-machine copy:

```bash
cd ~/.config/nixos   # or wherever NIXOS_DIR points
git remote -v
# If the URL is wrong or incomplete, set it (HTTPS example — replace with your repo):
# git remote add origin https://github.com/<you>/<nixos-config-repo>.git
# git remote set-url origin git@github.com:<you>/<nixos-config-repo>.git   # SSH
git push -u origin main   # branch name may differ
```

Rename a oddly named remote (e.g. **`nixos`**) to **`origin`** if you prefer: **`git remote rename nixos origin`** after fixing **`remote.*.url`**.

# Reference — previous NixOS configuration (other machine)

Your last install was **not** this Framework laptop: treat `hardware-configuration.nix`, **hostname**, and **`system.stateVersion`** as **new-machine decisions**. This file pulls out what is **portable** so you can merge it into the current roadmap (Phases 2–4) without copying the old file wholesale.

## What does *not* transfer blindly

- [ ] **`./hardware-configuration.nix`** — regenerate on the Framework (disk, kernel modules, initrd).
- [ ] **`networking.hostName`** — set a new name if you like (was `nixos`).
- [ ] **`users.users.*`** — username was `wiz`; keep or change, but **groups** (`wheel`, `networkmanager`, `video`) are a good default to reapply.
- [ ] **`system.stateVersion`** — set to match the **first** NixOS version on **this** install (see upstream comment); do not copy `24.05` by reflex.
- [ ] **Desktop stack** — old config used **SDDM + Plasma 6**. **Theseus** stays on **Plasma (Wayland) + tiling** + **Kitty** + **focus-follows-mouse**. Reuse *services* (audio, network) and *preferences* (locale, zsh taste); **do not** stack a second full compositor (e.g. Sway) on top unless you explicitly change plans.

## Strong candidates to carry over (system-level)

These match common “daily driver” needs and align with Phase 2 unless you explicitly want something slimmer.

| Area | Old setting | Notes |
|------|-------------|--------|
| Network | `networking.networkmanager.enable = true` | Standard for laptops. |
| Time / locale | `America/Los_Angeles`, `en_US.UTF-8`, `i18n.extraLocaleSettings` | Adjust if you moved. |
| Keyboard | `services.xserver.layout = "us"` | For X11 bits; Wayland sessions often set layout separately—replicate your layout there too. |
| Printing | `services.printing.enable = true` | Phase 2 checklist. |
| Bluetooth | `hardware.bluetooth.enable` + `powerOnBoot` | Framework often used with BT peripherals. |
| Polkit | `security.polkit.enable = true` | Typical for desktop sessions. |
| Audio | PipeWire + ALSA + Pulse compat, `pulseaudio` off, `rtkit` | Matches modern NixOS defaults. |
| Input | `services.xserver.libinput.enable = true` | Touchpad/trackpoint. |
| Swap | Old machine used **`zramSwap` 25%** | On **Theseus**, **swap is already configured** — **no zram** per [Q10](./00-audit-priorities-and-risks.md#q10-zram-and-swap). |
| Fonts | `fonts.packages` — `nerdfonts` with FiraCode, DroidSansMono, Iosevka | Fits Phase 4 / rice; subset is a matter of taste. |
| Unfree | `nixpkgs.config.allowUnfree = true` | Needed for Steam, Discord, Obsidian, etc., if you keep those. |

## Shell and editor preferences (reconcile with Phase 3)

Old config enabled **zsh** globally and used **`programs.zsh`** with **oh-my-zsh** (theme `jonathan`, plugins: git, npm, history, node, deno, fzf), plus **`autosuggestions`**, **`syntaxHighlighting`**, **`zsh-autoenv`**, **`shellAliases`**, and **`programs.thefuck`**.

- [ ] **Parity** — reproduce the *behavior* you care about (theme vs plain prompt, plugin set) via **Home Manager** and/or **chezmoi** ([debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main)), not necessarily another copy-paste of system-wide oh-my-zsh unless you prefer that.
- [ ] **`users.defaultUserShell` / `users.users.<name>.shell`** — `pkgs.zsh` still makes sense with Phase 2.
- [ ] **Env** — `EDITOR` / `VISUAL` / `SYSTEMD_EDITOR` = `micro` matches your old habit; keep or point at Neovim if you switch.

## Programs you had in `environment.systemPackages` (pick what to restore)

Use this as a **shopping list**; move suitable items to **`home.packages`** later if you adopt Home Manager.

**CLI / tooling**

- `wget`, `git`, `gh`, `nodejs_20`, `gcc`, `gnumake`, `sqlite`, `python3`, `tmux`
- `nix-search-cli`, `bottom`, `fzf`, `micro`, `neofetch`, `cbonsai`, `peaclock`, `alejandra`, `libnotify`
- `openvpn`, `xd` (verify you still need these)
- `wev`, `brightnessctl` (input/display debugging and brightness—common with Wayland tiling)

**GUI / productivity**

- `vscode`, `kdePackages.kate` (KDE-centric if you leave Plasma behind—replace with editor of choice)
- `vlc`, `discord`, `obsidian`, `bitwarden-desktop`, `libreoffice`

**Games / special**

- `steam` (also `programs.steam` with firewall toggles in old config)
- `appimage-run`, `fuse` (AppImages / Slippi-era workflow—keep only if still relevant)

**Misc**

- `libsForQt5.kconfig` — was marked “temp”; only if something still needs it.
- `beauty-line-icon-theme` — icon theme; Phase 4.

**Commented in old config (aligns with current plan)**

- Hyprland, Sway, Wayland helpers (`grim`, `slurp`, `wl-clipboard`, `waybar`, `dunst`, `rofi-wayland`, `swww`, Kitty) — **archive** from the old config; **Theseus** uses **Plasma + tiling** + **Kitty**, not a standalone wlroots WM.

## `programs.*` blocks worth revisiting

- [ ] **`programs.firefox.enable = true`** — simple system-wide browser enable.
- [ ] **`programs.steam`** — only if you still use Steam; firewall options were enabled for Remote Play / dedicated server / LAN transfers.
- [ ] **`environment.shells` + `environment.variables`** — keep `zsh` in `environment.shells`; variables as you like.

## Suggested order in *this* roadmap

1. **Phase 2** — NetworkManager, PipeWire, Bluetooth, printing, locale/timezone, fonts (if you want them early), then **Kitty + zsh** per plan; add packages from the list **incrementally** so failures are easy to bisect.
2. **Phase 3** — Port oh-my-zsh–equivalent (or slimmer) settings into Home Manager/chezmoi.
3. **Phase 4** — Icons, wallpaper tooling (`swww` etc.), bar/launcher if not already set from tiling choice.

## Checklist — “I want this again on the Framework”

<!-- Check what applies; leave blank rows for notes -->

- [ ] Same timezone / locale as before
- [ ] **No `zramSwap`** on Theseus — **swap already configured** ([Q10](./00-audit-priorities-and-risks.md#q10-zram-and-swap))
- [ ] Same zsh “feel” (oh-my-zsh or slimmer)
- [ ] Firefox / Steam / gaming firewall options
- [ ] Same package clusters: dev, media, chat, notes, VPN
- [x] **Session stack:** **Plasma (Wayland) + tiling** (not Hyprland/Sway on this machine)

## Notes

<!-- Paste snippets you actually carried over, or link to your new flake/configuration repo -->

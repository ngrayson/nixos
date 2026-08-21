# Phase 2: Slim desktop profile + slim home-manager

Goal: Hyprland session with the same look/feel as Tawa/Theseus but a fraction
of the closure: no Plasma, no Steam/Slippi, no VPN, no workstation app pile.

Strategy: **purely additive**. Hearth gets its own profile and its own HM
entrypoint; `common/system.nix` and `home/default.nix` are not modified, so
Tawa/Theseus cannot regress.

## 1. `profiles/media-desktop.nix` (new)

Imports `common/base.nix` (flakes, allowUnfree, TZ/locale) and re-declares only
the GUI core Hearth needs, cherry-picked from `common/system.nix`:

- Boot: systemd-boot + `canTouchEfiVariables` (skip Plymouth to keep closure
  small — optional, decide at implementation)
- `networking.networkmanager.enable`
- Bluetooth + blueman (Surface keyboards/remotes may pair over BT)
- `security.polkit.enable`, `security.rtkit.enable`
- PipeWire (alsa + pulse), `services.libinput.enable`
- SDDM with the breeze-login theme derivation (copy the `sddmThemeBreezeLogin`
  let-block pattern from `common/system.nix`; it only depends on
  `kdePackages.plasma-desktop` as a package, NOT on enabling Plasma)
- `programs.hyprland.enable = true`; `services.displayManager.defaultSession =
  "hyprland"`; xdg portal default `["hyprland" "gtk"]`
- `programs.dconf.enable` (Stylix GTK target needs it)
- User `wiz` (wheel, networkmanager, zsh) + `users.defaultUserShell`
- `programs.firefox.enable` (Jellyfin web UI + general use)
- Fonts: `nerd-fonts.iosevka-term-slab` (quickshell glyphs) — matches shared
- System packages (CLI + essentials only):
  `wget micro gh btop fzf tree libnotify alejandra nix-search-cli kitty
  brightnessctl vlc ffmpeg topgrade glow`
- Home-manager block (mirrors `common/system.nix` shape, slim imports):

```nix
home-manager = {
  useGlobalPkgs = true;
  backupFileExtension = "hm-backup";
  extraSpecialArgs = {
    stylixModule = inputs.stylix.homeModules.stylix;
  };
  users.wiz.imports = [../home/media.nix];
};
```

Note: `extraSpecialArgs` must satisfy every module the slim HM set imports; if
a kept module expects `slippi-nix-src`, drop that module rather than plumbing
slippi into a media host.

## 2. `home/media.nix` (new slim HM entrypoint)

Audit `home/default.nix` and keep only:

| Keep | Why |
|------|-----|
| `theme/` + `stylix.nix` | color system (phase 3) |
| `wayland/hyprland.nix` | the session itself |
| `services/dunst.nix`, polkit agent | notifications, auth prompts |
| `services/hypridle.nix` + `hypr/scripts.nix` | lock/DPMS — ONLY if the Slippi guards degrade gracefully; otherwise write a minimal idle config inline |
| `programs/zsh.nix`, `programs/git.nix` | shell parity |
| `xdg/` kitty + fastfetch configs | terminal look, fastfetch |
| quickshell config | bar/UX parity — verify no spotifyd/albert deps first |

Explicitly dropped: slippi, spotifyd, albert, firefox rice (keep plain
Firefox), photogimp, qt-palette/Kvantum (no Qt apps beyond SDDM), plasma
activation scripts, `gui-session-launch.nix` (check: may be needed for
Hyprland autostart — audit).

Set `home.stateVersion` in `media.nix` (use `"25.11"` if importing
`session.nix`, else declare `"26.05"` — first HM install on this machine).

If a kept HM module hard-references a dropped one, prefer: (a) drop it too,
(b) write a small Hearth-local replacement under `home/`, and only as a last
resort (c) edit the shared module — with the parity guardrail run.

## 3. Theme prerequisite

HM eval throws until Hearth exists in `home/theme/hosts.nix` — phase 3's
`hosts.nix` entry (with a placeholder scheme like `izar` if phase 3 isn't
ready) must be included in the first successful build.

## 4. First switch (phases 1+2+minimal 3 together)

```bash
git add -A
os-rebuild check --host Hearth     # or: nix flake check
os-rebuild build --host Hearth
os-rebuild switch --host Hearth    # sudo nixos-rebuild switch --flake .#Hearth
```

Expect: SDDM login -> Hyprland session, kitty + zsh + fastfetch working,
NetworkManager reconnects Wi-Fi (may need re-auth after hostname change).

## Verification

- `nixos-rebuild list-generations` shows the flake generation
- Hyprland session launches; quickshell bar renders; dunst notifies
- Closure sanity: `nix path-info -Sh /run/current-system` — expect several GiB
  smaller than a Tawa-style build (no Plasma/Steam/Blender/etc.)
- Parity guardrail (README) on Tawa/Theseus/Gcp

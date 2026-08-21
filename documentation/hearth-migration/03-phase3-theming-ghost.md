# Phase 3: Ghost theme + telePole wallpaper

Goal: preserve the look the user cares about — the terminal palette shown by
fastfetch (Konsole "Ghost Color Scheme") and the desktop wallpaper
(`~/Documents/Tomes/_assets/telePole.jpg`) — expressed through the repo's
existing theme system (`home/theme/`), so Stylix/kitty/Hyprland/quickshell all
pick it up the same way Izar does on Tawa.

## 1. Wallpaper into the repo

```bash
cp ~/Documents/Tomes/_assets/telePole.jpg ./telePole.jpg   # repo root, like izar-utopia.png
git add telePole.jpg
```

## 2. `home/theme/schemes/ghost.nix` (new)

Ported from `~/.local/share/konsole/Ghost Color Scheme.colorscheme` (full hex
table in [00-analysis](./00-analysis-current-vs-flake.md)). Proposed mapping,
following the structure of `home/theme/schemes/izar.nix`:

```nix
# Ghost — dark teal + aqua, terracotta/lilac accents. Ported from the Surface
# Konsole "Ghost Color Scheme".
{
  name = "Ghost";
  slug = "ghost";
  polarity = "dark";

  tokens = {
    void = "122221";      # Konsole Background
    depth = "182D2B";     # BackgroundFaint
    chrome = "203D3B";    # Color0
    surface = "2D5451";   # Color0Faint
    border = "3C6784";    # Color4
    muted = "656565";     # Color7Faint
    text = "ACDCDD";      # Foreground
    strong = "C5FBFC";    # ForegroundIntense
    bright = "C5FBFC";
    accent = "2FC7BE";    # Color6 (cyan) — the scheme's signature hue
    selection = "2FC7BE";
    link = "70C1F7";      # Color4Intense
    visited = "A081B6";   # Color5
    sage = "3F947D";      # Color2
    mauve = "A081B6";
    error = "B15A65";     # Color1
    onAccent = "122221";
  };

  base16 = {
    base00 = "122221";  base01 = "182D2B";  base02 = "203D3B";  base03 = "2D5451";
    base04 = "96C8C9";  base05 = "ACDCDD";  base06 = "C5FBFC";  base07 = "FFFFFF";
    base08 = "B15A65";  base09 = "C46F5A";  base0A = "FD8D74";  base0B = "3F947D";
    base0C = "2FC7BE";  base0D = "70C1F7";  base0E = "A081B6";  base0F = "994651";
  };

  # Direct port of the Konsole normal/intense pairs.
  kitty = {
    background = "122221";
    foreground = "acdcdd";
    cursor = "2fc7be";
    cursor_text_color = "122221";
    selection_background = "2fc7be";
    selection_foreground = "122221";
    url_color = "70c1f7";
    color0 = "203d3b";  color8 = "20f3e5";
    color1 = "b15a65";  color9 = "ec446c";
    color2 = "3f947d";  color10 = "39e2b2";
    color3 = "c46f5a";  color11 = "fd8d74";
    color4 = "3c6784";  color12 = "70c1f7";
    color5 = "a081b6";  color13 = "e0b5ff";
    color6 = "2fc7be";  color14 = "3cfdf0";
    color7 = "b2b2b2";  color15 = "ffffff";
  };
}
```

Tuning note: the old KDE accent was terracotta `#B4655A`. If teal accents feel
wrong in Hyprland borders/quickshell, swap `accent`/`selection` to `C46F5A`
(one-line change; palette slots keep both hues either way).

## 3. Register the scheme and the host

- `home/theme/default.nix`: add `ghost = import ./schemes/ghost.nix;` to the
  `schemes` attrset (additive; existing hosts unaffected).
- `home/theme/hosts.nix` (additive):

```nix
Hearth = {
  scheme = "ghost";
  wallpaper = ../../telePole.jpg;
  wallpaperName = "telePole.jpg";
  spanMonitors = false;
};
```

Both edits touch shared files but are additive; run the parity guardrail.

## 4. Terminal font

Konsole used **Iosevka Nerd Font Mono 12**. The repo's Stylix font stack is
JetBrains Mono / Inter / Source Serif 4 and the shared fonts package is
`nerd-fonts.iosevka-term-slab`. Decision: accept the repo kitty font for
parity, but if the fastfetch look must match exactly, set kitty's font to an
Iosevka Nerd Font variant in the slim HM (Hearth-local override, not a shared
edit).

## Verification

- `kitty` shows the ghost palette (compare against a Konsole window before
  retiring it); `fastfetch` colors match the old look
- Hyprland border/quickshell colors derive from ghost tokens
- Wallpaper renders via Stylix hyprpaper (spanMonitors=false path)
- Parity guardrail: Tawa/Theseus toplevels identical before/after

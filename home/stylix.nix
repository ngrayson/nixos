# Stylix via Home Manager only. The module is supplied by the pinned flake input.
#
# Palette + wallpaper come from [`theme/hosts.nix`](./theme/hosts.nix). Tawa spans
# wallpaper via [`services/rwpspread-wallpaper.nix`](./services/rwpspread-wallpaper.nix);
# other hosts preload `stylix.image` as Hyprpaper fallback (`wallpaper = ,<path>`).
#
# GTK: Stylix uses theme name `adw-gtk3` (engine) plus generated `gtk.css` (Base16 colors) —
# `gsettings get org.gnome.desktop.interface gtk-theme` may show `adw-gtk3` while the
# active palette still applies.
{
  stylixModule,
  pkgs,
  config,
  lib,
  ...
}: let
  b = config.theme.base16;
  # The 16 slots Stylix needs, listed rather than taken from `b` wholesale, so a
  # scheme that forgets one fails here instead of quietly theming from 15.
  base16Slots = [
    "base00"
    "base01"
    "base02"
    "base03"
    "base04"
    "base05"
    "base06"
    "base07"
    "base08"
    "base09"
    "base0A"
    "base0B"
    "base0C"
    "base0D"
    "base0E"
    "base0F"
  ];
  # Passed to Stylix as an attrset, NOT as a generated YAML file.
  #
  # This used to be a `pkgs.writeText` whose store path was handed to
  # `stylix.base16Scheme`. Stylix reads that file during evaluation, so a
  # derivation had to be realised before the config could evaluate at all --
  # import-from-derivation. `nix flake check --no-build` (what `os-rebuild
  # check` runs) evaluates with a READ-ONLY store, so it could not realise it
  # and died with `path '...-lilac-ash-base16.yaml.drv' is not valid`, while
  # `os-rebuild build` on the same tree succeeded.
  #
  # It failed on Theseus specifically because Tawa is `izar` and Theseus is
  # `lilac-ash`: nothing Tawa builds keeps Theseus's YAML alive, so `nix-gc`
  # reaped it and `check` stayed broken from then on.
  #
  # `stylix.base16Scheme` accepts `path | lines | attrs`; the attrs branch skips
  # the YAML parse and its checker derivation entirely, so no store realisation
  # can be required to evaluate this config.
  base16Scheme = {
    system = "base16";
    name = config.theme.name;
    author = "stellarium home/theme";
    variant = config.theme.polarity;
    # `slug` is deliberately not set: Stylix derives it from `name` exactly as
    # it did when parsing the YAML, so generated theme filenames do not move.
    palette = lib.listToAttrs (map (k: lib.nameValuePair k "#${b.${k}}") base16Slots);
  };
in {
  imports = [stylixModule];

  stylix = {
    enable = true;
    # Explicit targets only (avoids surprise enables as Stylix adds defaults). See MIGRATION.md § Stylix.
    autoEnable = false;

    polarity = config.theme.polarity;
    inherit base16Scheme;
    image = builtins.path {
      path = config.theme.wallpaper;
      name = config.theme.wallpaperName;
    };

    fonts = {
      monospace = {
        package = pkgs.jetbrains-mono;
        name = "JetBrains Mono";
      };
      sansSerif = {
        package = pkgs.inter;
        name = "Inter Variable";
      };
      serif = {
        package = pkgs.source-serif;
        name = "Source Serif 4";
      };
      sizes = {
        applications = 11;
        terminal = 12;
        desktop = 10;
      };
    };

    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    targets = {
      fontconfig.enable = true;
      gtk.enable = true;

      kitty.enable = false;
      vscode.enable = false;

      # KDE color scheme is [`programs/qt-palette.nix`](./programs/qt-palette.nix).
      qt.enable = false;

      hyprland = {
        enable = true;
        hyprpaper.enable = !config.theme.spanMonitors;
      };
    };
  };

  # Stylix's `gtk` target only writes the theme + Base16 `gtk.css`; it never sets the freedesktop
  # appearance preference. Apps that follow the *system* setting (Electron/Chromium, Firefox "System
  # theme", libadwaita) read `org.gnome.desktop.interface color-scheme` through the settings portal, so
  # without this they render light on an otherwise dark desktop. HM maps this to dconf `prefer-dark`
  # plus `gtk-application-prefer-dark-theme` / `gtk-interface-color-scheme` in both settings.ini files.
  gtk.colorScheme = "dark";

  # Plasma rewrites ~/.gtkrc-2.0 as a regular file. Without force, HM tries to
  # rename it to .gtkrc-2.0.hm-backup and fails if that backup already exists.
  gtk.gtk2.force = true;

  # Leftover files from the reverted Wallust experiment; not referenced by Stylix HM `gtk.css` but confuse
  # inspection and could interact badly if GTK ever loads them from the config dir.
  home.activation.stylixRemoveStaleGtkCss = lib.hm.dag.entryAfter ["writeBoundary"] ''
    for f in \
      "${config.home.homeDirectory}/.config/gtk-3.0/wallust-colors.css" \
      "${config.home.homeDirectory}/.config/gtk-4.0/wallust-colors.css" \
      "${config.home.homeDirectory}/.config/gtk-3.0/colors.css" \
      "${config.home.homeDirectory}/.config/gtk-4.0/colors.css"
    do
      if [ -f "$f" ] && [ ! -L "$f" ]; then
        $DRY_RUN_CMD rm -f "$f"
      fi
    done
  '';
}

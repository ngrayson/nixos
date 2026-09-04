# Kitty palette, VS Code theme extension, Obsidian vault theme,
# Quickshell bar/lock JSON.
{
  config,
  lib,
  pkgs,
  ...
}: let
  t = config.theme;
  k = t.kitty;
  hx = t.hex;
  hash = c: "#" + lib.toLower (lib.removePrefix "#" c);

  kittyPalette = ''
    # Generated from home/theme — do not edit. Scheme: ${t.name}
    background            ${hash k.background}
    foreground            ${hash k.foreground}
    cursor                ${hash k.cursor}
    cursor_text_color     ${hash k.cursor_text_color}

    selection_background  ${hash k.selection_background}
    selection_foreground  ${hash k.selection_foreground}

    url_color             ${hash k.url_color}

    color0  ${hash k.color0}
    color1  ${hash k.color1}
    color2  ${hash k.color2}
    color3  ${hash k.color3}
    color4  ${hash k.color4}
    color5  ${hash k.color5}
    color6  ${hash k.color6}
    color7  ${hash k.color7}
    color8  ${hash k.color8}
    color9  ${hash k.color9}
    color10 ${hash k.color10}
    color11 ${hash k.color11}
    color12 ${hash k.color12}
    color13 ${hash k.color13}
    color14 ${hash k.color14}
    color15 ${hash k.color15}
  '';

  vscodeTheme = {
    name = t.name;
    type = "dark";
    colors = {
      "editor.background" = hx.void;
      "editor.foreground" = hx.text;
      "editor.lineHighlightBackground" = hx.depth;
      "editor.selectionBackground" = hx.selection + "99";
      "editorCursor.foreground" = hx.accent;
      "editorLineNumber.foreground" = hx.muted;
      "editorLineNumber.activeForeground" = hx.text;
      "editorWidget.background" = hx.depth;
      "editorWidget.border" = hx.border;
      "sideBar.background" = hx.depth;
      "sideBar.foreground" = hx.text;
      "sideBar.border" = hx.border;
      "activityBar.background" = hx.void;
      "activityBar.foreground" = hx.accent;
      "activityBar.inactiveForeground" = hx.muted;
      "statusBar.background" = hx.depth;
      "statusBar.foreground" = hx.text;
      "statusBar.noFolderBackground" = hx.chrome;
      "titleBar.activeBackground" = hx.void;
      "titleBar.activeForeground" = hx.text;
      "titleBar.inactiveBackground" = hx.depth;
      "titleBar.inactiveForeground" = hx.muted;
      "tab.activeBackground" = hx.surface;
      "tab.inactiveBackground" = hx.void;
      "tab.activeForeground" = hx.text;
      "tab.inactiveForeground" = hx.muted;
      "tab.activeBorder" = hx.accent;
      "tab.border" = hx.void;
      "panel.background" = hx.void;
      "panel.border" = hx.border;
      "terminal.background" = hash k.background;
      "terminal.foreground" = hash k.foreground;
      "terminal.ansiBlack" = hash k.color0;
      "terminal.ansiRed" = hash k.color1;
      "terminal.ansiGreen" = hash k.color2;
      "terminal.ansiYellow" = hash k.color3;
      "terminal.ansiBlue" = hash k.color4;
      "terminal.ansiMagenta" = hash k.color5;
      "terminal.ansiCyan" = hash k.color6;
      "terminal.ansiWhite" = hash k.color7;
      "terminal.ansiBrightBlack" = hash k.color8;
      "terminal.ansiBrightRed" = hash k.color9;
      "terminal.ansiBrightGreen" = hash k.color10;
      "terminal.ansiBrightYellow" = hash k.color11;
      "terminal.ansiBrightBlue" = hash k.color12;
      "terminal.ansiBrightMagenta" = hash k.color13;
      "terminal.ansiBrightCyan" = hash k.color14;
      "terminal.ansiBrightWhite" = hash k.color15;
      "focusBorder" = hx.accent;
      "foreground" = hx.text;
      "widget.border" = hx.border;
      "input.background" = hx.depth;
      "input.foreground" = hx.text;
      "input.border" = hx.border;
      "dropdown.background" = hx.depth;
      "list.activeSelectionBackground" = hx.surface;
      "list.hoverBackground" = hx.surface;
      "list.inactiveSelectionBackground" = hx.chrome;
      "button.background" = hx.accent;
      "button.foreground" = hx.onAccent;
      "badge.background" = hx.accent;
      "badge.foreground" = hx.onAccent;
      "minimap.background" = hx.void;
    };
    tokenColors = [
      {
        scope = ["comment" "punctuation.definition.comment"];
        settings.foreground = hx.muted;
      }
      {
        scope = ["keyword" "storage.type" "storage.modifier"];
        settings.foreground = hx.mauve;
      }
      {
        scope = ["string" "markup.inline.raw"];
        settings.foreground = hx.sage;
      }
      {
        scope = ["constant" "constant.numeric" "variable.other.constant"];
        settings.foreground = hx.accent;
      }
      {
        scope = ["entity.name.function" "support.function"];
        settings.foreground = hx.link;
      }
      {
        scope = ["variable" "entity.name.tag"];
        settings.foreground = hx.text;
      }
      {
        scope = ["entity.name.type" "support.type" "support.class"];
        settings.foreground = hx.bright;
      }
      {
        scope = ["invalid"];
        settings.foreground = hx.error;
      }
    ];
  };

  # `name` is the extension id's name half: VS Code resolves the unique id as
  # `<publisher>.<name>`, so this is deliberately `desktop-theme` (→ id
  # `stellarium.desktop-theme`) and NOT the old `stellarium-desktop-theme`.
  # The previous folder-drop delivery had id `stellarium.stellarium-desktop-theme`
  # and VS Code poisoned it into `.obsolete`; a fresh id sidesteps that marker
  # entirely. Version bumped so the registry entry differs from the stale one.
  vscodePackage = {
    name = "desktop-theme";
    displayName = "Stellarium desktop theme";
    version = "0.0.2";
    publisher = "stellarium";
    engines.vscode = "^1.0.0";
    contributes.themes = [
      {
        label = t.name;
        uiTheme = "vs-dark";
        path = "./themes/theme.json";
      }
    ];
  };

  vscodeExtUniqueId = "${vscodePackage.publisher}.${vscodePackage.name}";

  # Deliver the theme as a real extension derivation, laid out the way Home
  # Manager's `programs.vscode` (mutableExtensionsDir) consumes it: the module
  # symlinks `~/.vscode/extensions/<uniqueId>` → `$out/share/vscode/extensions/
  # <uniqueId>` and reads `.vscodeExtUniqueId` / `.vscodeExtPublisher` /
  # `.version` off the derivation for `.extensions-immutable.json`. Built with
  # runCommand rather than `vscode-utils.buildVscodeExtension` because the
  # latter's unpack phase assumes a `.vsix`/`extension/` source root; these are
  # loose generated files, so a direct copy is simpler and unambiguous.
  vscodeThemeExtension =
    pkgs.runCommand "vscode-extension-${vscodePackage.name}-${vscodePackage.version}"
    {
      vscodeExtPublisher = vscodePackage.publisher;
      vscodeExtName = vscodePackage.name;
      inherit vscodeExtUniqueId;
      inherit (vscodePackage) version;
    }
    ''
      dst="$out/share/vscode/extensions/${vscodeExtUniqueId}"
      mkdir -p "$dst/themes"
      cp ${pkgs.writeText "package.json" (builtins.toJSON vscodePackage)} "$dst/package.json"
      cp ${pkgs.writeText "theme.json" (builtins.toJSON vscodeTheme)} "$dst/themes/theme.json"
    '';

  # VS Code marked the old folder-drop extension as removed
  # (`stellarium.stellarium-desktop-theme-0.0.1` in `.obsolete`) and skips
  # anything listed there even on a directory rescan. The new id is unaffected,
  # but clear the dead marker and the stale loose folder so the extensions dir
  # doesn't carry cruft. jq is safe here: `.obsolete` is strict JSON, and the
  # file may be absent (not an error).
  patchVscodeObsolete = pkgs.writeShellScript "clear-vscode-obsolete-theme" ''
    set -euo pipefail
    exts="$HOME/.vscode/extensions"
    obsolete="$exts/.obsolete"
    if [ -f "$obsolete" ]; then
      tmp=$(mktemp)
      if ${lib.getExe pkgs.jq} 'del(."stellarium.stellarium-desktop-theme-0.0.1")' \
        "$obsolete" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$obsolete"
      else
        rm -f "$tmp"
      fi
    fi
    rm -rf "$exts/stellarium.desktop-theme-0.0.1"
  '';

  obsidianCss = ''
    /* Generated from home/theme — ${t.name} */
    :root {
      --default-font: "IosevkaTermSlab NFM", "JetBrains Mono", monospace;
      --font-text: "IosevkaTermSlab NFM", "JetBrains Mono", monospace;
      --font-interface: "IosevkaTermSlab NFM", "Inter Variable", sans-serif;
      --font-monospace: "IosevkaTermSlab NFM", "JetBrains Mono", monospace;
    }

    .theme-dark {
      color-scheme: dark;
      --background-primary: ${hx.depth};
      --background-primary-alt: ${hx.depth};
      --background-secondary: ${hx.chrome};
      --background-secondary-alt: ${hx.chrome};
      --titlebar-background: ${hx.chrome};
      --titlebar-background-focused: ${hx.chrome};
      --background-modifier-border: ${hx.border};
      --background-modifier-border-hover: ${hx.border};
      --background-modifier-border-focus: ${hx.accent};
      --text-normal: ${hx.text};
      --text-muted: ${hx.mauve};
      --text-faint: ${hx.muted};
      --text-on-accent: ${hx.onAccent};
      --bold-color: ${hx.bright};
      --italic-color: ${hx.strong};
      --text-selection: color-mix(in srgb, ${hx.selection} 55%, transparent);
      --text-highlight-bg: color-mix(in srgb, ${hx.selection} 35%, transparent);
      --link-color: ${hx.link};
      --link-color-hover: ${hx.bright};
      --link-external-color: ${hx.link};
      --link-external-color-hover: ${hx.bright};
      --interactive-normal: ${hx.chrome};
      --interactive-hover: ${hx.surface};
      --interactive-accent: ${hx.accent};
      --interactive-accent-hover: ${hx.selection};
      --background-modifier-form-field: ${hx.depth};
      --scrollbar-bg: ${hx.void};
      --scrollbar-thumb-bg: ${hx.border};
      --scrollbar-active-thumb-bg: ${hx.accent};
      --h1-color: ${hx.bright};
      --h2-color: ${hx.strong};
      --h3-color: ${hx.sage};
      --h4-color: ${hx.accent};
      --h5-color: ${hx.link};
      --h6-color: ${hx.mauve};
      --code-normal: ${hx.text};
      --code-background: ${hx.void};
    }
  '';

  obsidianManifest = builtins.toJSON {
    name = t.name;
    version = "1.0.0";
    minAppVersion = "1.0.0";
    author = "stellarium";
    description = "Generated from ~/.config/nixos/home/theme";
  };

  vaultTheme = "${t.obsidianVault}/.obsidian/themes/${t.name}";

  patchAppearance = pkgs.writeShellScript "patch-obsidian-appearance" ''
    set -euo pipefail
    appearance="$HOME/${t.obsidianVault}/.obsidian/appearance.json"
    mkdir -p "$(dirname "$appearance")"
    if [ ! -f "$appearance" ]; then
      echo '{}' > "$appearance"
    fi
    tmp=$(mktemp)
    ${lib.getExe pkgs.jq} \
      --arg theme ${lib.escapeShellArg t.name} \
      --arg accent ${lib.escapeShellArg hx.accent} \
      '.cssTheme = $theme | .accentColor = $accent | .theme = "obsidian"' \
      "$appearance" > "$tmp"
    mv "$tmp" "$appearance"
  '';

  patchEditors = pkgs.writeShellScript "patch-editor-color-theme" ''
        set -euo pipefail
        theme=${lib.escapeShellArg t.name}
        # Code settings are JSONC (trailing commas, optional comments). Strict
        # jq fails those files and takes home-manager-wiz.service down with them.
        py=${lib.getExe (pkgs.python3.withPackages (ps: [ps.json5]))}
        patch() {
          local f="$1"
          mkdir -p "$(dirname "$f")"
          if [ ! -f "$f" ]; then
            echo '{}' > "$f"
          fi
          tmp=$(mktemp)
          "$py" - "$f" "$theme" "$tmp" <<'PY'
    import json, json5, sys

    path, theme, out = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(path, "r", encoding="utf-8") as fh:
        raw = fh.read().strip() or "{}"
    data = json5.loads(raw)
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected a JSON object, got {type(data).__name__}")
    data["workbench.colorTheme"] = theme
    data["workbench.preferredDarkColorTheme"] = theme
    data["window.autoDetectColorScheme"] = False
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent="\t", ensure_ascii=False)
        fh.write("\n")
    PY
          mv "$tmp" "$f"
        }
        patch "$HOME/.config/Code/User/settings.json"
  '';

  wallpaperStore = builtins.path {
    path = t.wallpaper;
    name = t.wallpaperName;
  };

  quickshellTheme = {
    inherit (t) name;
    bg = hx.void;
    err = hx.error;
    ink = hx.onAccent;
    inherit (hx) depth chrome surface border muted text strong bright accent selection link visited sage mauve;
    wallpaper = "${wallpaperStore}";
  };
in {
  xdg.configFile."kitty/palette.conf" = {
    text = kittyPalette;
    force = true;
  };

  xdg.configFile."quickshell/theme.json" = {
    text = builtins.toJSON quickshellTheme;
    force = true;
  };

  # VS Code loads the generated theme as a registered extension (see
  # `vscodeThemeExtension`). `mutableExtensionsDir` (the default) lets HM
  # regenerate `extensions.json` via `code --list-extensions` on change while
  # leaving Nick's gallery-installed extensions in place. Deliberately NO
  # `profiles.default.userSettings`: `~/.config/Code/User/settings.json` is
  # JSONC and Settings-Sync'd, and is patched in place by `patchEditors` above —
  # handing it to HM would take ownership of the whole file.
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    mutableExtensionsDir = true;
    profiles.default.extensions = [vscodeThemeExtension];
  };

  home.file = {
    "${vaultTheme}/theme.css" = {
      text = obsidianCss;
      force = true;
    };
    "${vaultTheme}/manifest.json" = {
      text = obsidianManifest;
      force = true;
    };
  };

  home.activation.obsidianColorTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${patchAppearance}
  '';

  home.activation.editorColorTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${patchEditors}
  '';

  home.activation.clearVscodeObsoleteTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${patchVscodeObsolete}
  '';
}

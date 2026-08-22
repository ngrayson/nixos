# Declaratively enable Albert Python sub-plugins (Emoji, Firefox bookmarks, Kill, Wikipedia).
# Websearch + DuckDuckGo: use ~/.config/albert/websearch/engines.json (trigger `dd` is typical).
# Firefox sub-plugin (albert-plugin-python-firefox) only reads `~/.mozilla/firefox` (see upstream
# `__init__.py`). On NixOS/XDG, profiles often live in `~/.config/mozilla/firefox` with no
# `~/.mozilla` tree, so the plugin throws “No Firefox profiles found” and never appears. The
# activation block symlinks the legacy path to the real profile directory when that’s the case.
# Profiles still need `places.sqlite` and `favicons.sqlite` (use Firefox at least once).
# The Python bundle requires Albert 34+ — `common/system.nix` overlays `pkgs.albert` from nixos-unstable.
#
# Theme: Widgets Box Model INI from `config.theme` (same keys as Tawa’s hand-written Izar.ini).
# `darkTheme` / `lightTheme` are upserted in the mutable config; the rest of that file stays local.
#
# If `~/.local/share/albert/python/plugins` or `.../venv` exists as a *file* (or a broken symlink),
# Albert/Qt may error when treating those paths (e.g. “could not be opened: it is a folder instead of a file”).
# The activation step below normalises layout: `plugins` is always a directory; a bogus `venv` file is removed
# so Albert can recreate the virtualenv.
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = "${config.home.homeDirectory}/.config/albert/config";
  hx = lib.mapAttrs (_: c: lib.toLower c) config.theme.hex;
  themeName = config.theme.name;
  upsertIni = pkgs.writeText "albert-upsert-ini.py" ''
    import re
    import sys

    path, section, key, value = sys.argv[1:5]
    try:
        text = open(path, encoding="utf-8").read()
    except FileNotFoundError:
        text = ""
    if text and not text.endswith("\n"):
        text += "\n"
    header = f"[{section}]"
    sec_re = re.compile(rf"^\[{re.escape(section)}\]\s*$", re.M)
    match = sec_re.search(text)
    if match is None:
        text += f"\n{header}\n{key}={value}\n"
    else:
        start = match.end()
        nxt = re.search(r"^\[", text[start:], re.M)
        end = start + nxt.start() if nxt else len(text)
        body = text[start:end]
        key_re = re.compile(rf"^{re.escape(key)}=.*$", re.M)
        if key_re.search(body):
            body = key_re.sub(f"{key}={value}", body, count=1)
        else:
            if body and not body.endswith("\n"):
                body += "\n"
            body += f"{key}={value}\n"
        text = text[:start] + body + text[end:]
    open(path, "w", encoding="utf-8").write(text)
  '';
in {
  # Systemd user unit rather than a Hyprland `exec-once`. exec-once pinned Albert to the store path
  # current at session start, so a rebuild never picked up a new build (including the unstable
  # overlay in common/system.nix) and a crash left no launcher until the next login. `ALT, Space`
  # runs `albert toggle`, which reaches this instance over D-Bus, so the keybind is unaffected.
  # Starts after the activation block below, which seeds ~/.config/albert/config and the plugin dirs.
  systemd.user.services.albert = {
    Unit = {
      Description = "Albert launcher";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = lib.getExe pkgs.albert;
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  xdg.dataFile."albert/widgetsboxmodel/themes/${themeName}.ini" = {
    force = true;
    text = ''
      ; ${themeName} — generated from home/theme. Reload Albert after switch.

      [palette]
      base=${hx.depth}
      text=${hx.text}
      window=${hx.void}
      window_text=${hx.text}
      button=${hx.chrome}
      button_text=${hx.text}
      highlight=${hx.accent}
      highlight_text=${hx.onAccent}
      placeholder_text=${hx.surface}
      link=${hx.link}
      link_visited=${hx.mauve}

      [window]
      input_background_brush=${hx.depth}
      input_border_brush=${hx.accent}
      input_trigger_color=${hx.accent}
      input_hint_color=${hx.surface}
      settings_button_color=${hx.chrome}
      settings_button_highlight_color=${hx.accent}
      result_item_selection_background_brush=${hx.accent}
      result_item_selection_border_brush=transparent
      result_item_selection_text_color=${hx.onAccent}
      result_item_selection_subtext_color=${hx.depth}
      result_item_text_color=${hx.text}
      result_item_subtext_color=${hx.link}
      action_item_selection_background_brush=${hx.accent}
      action_item_selection_border_brush=transparent
      action_item_selection_text_color=${hx.onAccent}
      action_item_text_color=${hx.text}
    '';
  };

  home.activation.albertPythonPlugins = lib.hm.dag.entryAfter ["writeBoundary"] ''
    _albert_cfg="${cfg}"
    mkdir -p "$(dirname "$_albert_cfg")"
    touch "$_albert_cfg"

    _albert_py="${config.home.homeDirectory}/.local/share/albert/python"
    _albert_plugins="$_albert_py/plugins"
    _albert_venv="$_albert_py/venv"

    mkdir -p "$_albert_py"
    if [ -L "$_albert_plugins" ] && [ ! -d "$_albert_plugins" ]; then
      rm -f "$_albert_plugins"
    elif [ -e "$_albert_plugins" ] && [ ! -d "$_albert_plugins" ]; then
      rm -f "$_albert_plugins"
    fi
    mkdir -p "$_albert_plugins"

    if [ -L "$_albert_venv" ] && [ ! -d "$_albert_venv" ]; then
      rm -f "$_albert_venv"
    elif [ -e "$_albert_venv" ] && [ ! -d "$_albert_venv" ]; then
      rm -f "$_albert_venv"
    fi

    _albert_ensure_section() {
      local section="$1"
      local esc="''${section//./\\.}"
      if ! grep -q "^\[$esc\]" "$_albert_cfg" 2>/dev/null; then
        printf '\n[%s]\nenabled=true\n' "$section" >> "$_albert_cfg"
      fi
    }

    _albert_ensure_section "python"
    _albert_ensure_section "python.emoji"
    _albert_ensure_section "python.firefox"
    _albert_ensure_section "python.kill"
    _albert_ensure_section "python.wikipedia"

    $DRY_RUN_CMD ${lib.getExe pkgs.python3} ${upsertIni} "$_albert_cfg" widgetsboxmodel darkTheme ${lib.escapeShellArg themeName}
    $DRY_RUN_CMD ${lib.getExe pkgs.python3} ${upsertIni} "$_albert_cfg" widgetsboxmodel lightTheme ${lib.escapeShellArg themeName}

    _albert_mozilla_legacy="${config.home.homeDirectory}/.mozilla/firefox"
    _albert_mozilla_xdg="${config.home.homeDirectory}/.config/mozilla/firefox"
    if [ -d "$_albert_mozilla_xdg" ] && [ ! -e "$_albert_mozilla_legacy" ]; then
      mkdir -p "${config.home.homeDirectory}/.mozilla"
      ln -sfn "$_albert_mozilla_xdg" "$_albert_mozilla_legacy"
    fi
  '';
}

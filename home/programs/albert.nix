# Declaratively enable Albert Python sub-plugins (Emoji, Firefox bookmarks, Kill, Wikipedia).
# Websearch + DuckDuckGo: use ~/.config/albert/websearch/engines.json (trigger `dd` is typical).
# Firefox sub-plugin (albert-plugin-python-firefox) only reads `~/.mozilla/firefox` (see upstream
# `__init__.py`). On NixOS/XDG, profiles often live in `~/.config/mozilla/firefox` with no
# `~/.mozilla` tree, so the plugin throws “No Firefox profiles found” and never appears. The
# activation block symlinks the legacy path to the real profile directory when that’s the case.
# Profiles still need `places.sqlite` and `favicons.sqlite` (use Firefox at least once).
# The Python bundle requires Albert 34+ — `common/system.nix` overlays `pkgs.albert` from nixos-unstable.
#
# If `~/.local/share/albert/python/plugins` or `.../venv` exists as a *file* (or a broken symlink),
# Albert/Qt may error when treating those paths (e.g. “could not be opened: it is a folder instead of a file”).
# The activation step below normalises layout: `plugins` is always a directory; a bogus `venv` file is removed
# so Albert can recreate the virtualenv.
{
  lib,
  config,
  ...
}: let
  cfg = "${config.home.homeDirectory}/.config/albert/config";
in {
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

    _albert_mozilla_legacy="${config.home.homeDirectory}/.mozilla/firefox"
    _albert_mozilla_xdg="${config.home.homeDirectory}/.config/mozilla/firefox"
    if [ -d "$_albert_mozilla_xdg" ] && [ ! -e "$_albert_mozilla_legacy" ]; then
      mkdir -p "${config.home.homeDirectory}/.mozilla"
      ln -sfn "$_albert_mozilla_xdg" "$_albert_mozilla_legacy"
    fi
  '';
}

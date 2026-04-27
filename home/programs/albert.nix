# Declaratively enable Albert Python sub-plugins (Emoji, Firefox bookmarks, Kill, Wikipedia).
# Websearch + DuckDuckGo: use ~/.config/albert/websearch/engines.json (trigger `dd` is typical).
# Firefox sub-plugin: needs ~/.mozilla/firefox with a profile containing places.sqlite *and* favicons.sqlite
# (open Firefox at least once). It is only bundled in Albert 34+ — use unstable albert in common/system.nix overlay.
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

    if [ ! -d "${config.home.homeDirectory}/.mozilla/firefox" ]; then
      echo "albert: Firefox plugin expects ~/.mozilla/firefox — launch Firefox once to create a profile." >&2
    fi
  '';
}

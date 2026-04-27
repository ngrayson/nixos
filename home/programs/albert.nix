# Declaratively enable Albert Python sub-plugins (Emoji, Firefox bookmarks, Kill, Wikipedia).
# Websearch + DuckDuckGo: use ~/.config/albert/websearch/engines.json (trigger `dd` is typical).
# The Firefox sub-plugin reads ~/.mozilla/firefox (matches `programs.firefox.enable` on NixOS).
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

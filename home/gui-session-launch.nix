# Installs ~/bin/gui-session-launch.sh for desktop Exec lines that need stdio capture.
# Cursor launchers use pkgs.code-cursor directly (home/xdg/data.nix); they do not use this wrapper.
{...}: {
  home.file."bin/gui-session-launch.sh" = {
    source = ./scripts/gui-session-launch.sh;
    executable = true;
  };
}

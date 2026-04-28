# Installs ~/bin/gui-session-launch.sh (used by desktop/applications/cursor*.desktop).
{...}: {
  home.file."bin/gui-session-launch.sh" = {
    source = ./scripts/gui-session-launch.sh;
    executable = true;
  };
}

# Installs ~/bin/gui-session-launch.sh for desktop Exec lines that need stdio capture.
{...}: {
  home.file."bin/gui-session-launch.sh" = {
    source = ./scripts/gui-session-launch.sh;
    executable = true;
  };
}

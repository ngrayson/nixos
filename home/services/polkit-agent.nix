# polkit-kde authentication agent as a systemd user unit.
#
# This was a Hyprland `exec-once`, which pins the agent to the store path that was current when the
# session started: a rebuild never replaces it (it had been serving an Aug-14 build for days) and
# nothing revives it if it dies — and a missing polkit agent makes GUI privilege prompts fail with
# no visible error. Unit shape follows hyprpaper / dunst in this repo.
{pkgs, ...}: {
  systemd.user.services.polkit-kde-agent = {
    Unit = {
      Description = "polkit-kde authentication agent";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}

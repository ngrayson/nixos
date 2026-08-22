# NetworkManager secrets agent. nmgui / nmcli cannot activate agent-owned
# profiles (AncientGlade) without this. systemd user unit so Hyprland
# rebuilds replace it — same shape as polkit-agent.nix.
{pkgs, ...}: {
  systemd.user.services.nm-applet = {
    Unit = {
      Description = "NetworkManager applet (secrets agent)";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}

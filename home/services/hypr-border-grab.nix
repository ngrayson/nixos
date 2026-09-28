# Turn Hyprland's border-drag resize off while an app that draws its own
# resize handles has focus, and back on otherwise.
#
# `general:resize_on_border` is deliberately global (hyprland.nix, Nick
# 2026-09-02), but Hyprland has no per-window switch for it, and with it on
# the compositor takes presses meant for Pixel Composer's own corner/edge
# handles. Measured 2026-09-28 with Nick: with the option off, PXC's own
# corner handles work; with it on they do not, and a per-window `rounding 0`
# (no curved-corner capture) did NOT help, so the grab ring itself is the
# problem. PXC cannot be resized by the compositor instead: it declares
# min == max size hints and only redraws for resizes it starts itself.
#
# Listens on Hyprland's event socket (socket2) rather than polling:
#   activewindow>>CLASS,TITLE   focus moved; toggle if the class changed group
#   configreloaded>>            `hyprctl reload` reset the option to the config
#                               value, so re-apply for whatever has focus now
# It only ever writes `resize_on_border`, and restores it to 1 on exit so a
# stopped service never leaves border resize off.
{
  lib,
  pkgs,
  ...
}: let
  # Classes that draw their own resize handles.
  ownHandleClasses = [
    "steam_app_2299510" # Pixel Composer, Steam/Proton build
  ];

  watcher = pkgs.writers.writePython3Bin "hypr-border-grab" {flakeIgnore = ["E501"];} ''
    import json
    import os
    import signal
    import socket
    import subprocess
    import sys

    HYPRCTL = "${pkgs.hyprland}/bin/hyprctl"
    OWN = set(${builtins.toJSON ownHandleClasses})
    state = {"applied": None}


    def keyword(on):
        subprocess.run([HYPRCTL, "keyword", "general:resize_on_border", "true" if on else "false"],
                       stdout=subprocess.DEVNULL, check=False)


    def apply(cls):
        want = cls not in OWN
        if want != state["applied"]:
            keyword(want)
            state["applied"] = want
            print(f"resize_on_border={int(want)} (focus class={cls or '-'})", flush=True)


    def active_class():
        out = subprocess.run([HYPRCTL, "activewindow", "-j"], capture_output=True, text=True).stdout
        try:
            return json.loads(out).get("class", "")
        except ValueError:
            return ""


    def restore(*_):
        keyword(True)
        sys.exit(0)


    signal.signal(signal.SIGTERM, restore)
    signal.signal(signal.SIGINT, restore)

    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    run = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    if not sig:
        sys.exit("HYPRLAND_INSTANCE_SIGNATURE unset")
    s = socket.socket(socket.AF_UNIX)
    s.connect(f"{run}/hypr/{sig}/.socket2.sock")
    apply(active_class())

    buf = b""
    while True:
        data = s.recv(4096)
        if not data:
            keyword(True)
            sys.exit("event socket closed")
        buf += data
        *lines, buf = buf.split(b"\n")
        for raw in lines:
            line = raw.decode(errors="replace")
            if line.startswith("activewindow>>"):
                apply(line[len("activewindow>>"):].split(",", 1)[0])
            elif line.startswith("configreloaded>>"):
                state["applied"] = None
                apply(active_class())
  '';
in {
  home.packages = [watcher];

  systemd.user.services.hypr-border-grab = {
    Unit = {
      Description = "Border-drag resize off while an own-handle app (Pixel Composer) has focus";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
      ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
    };
    Install.WantedBy = ["graphical-session.target"];
    Service = {
      ExecStart = lib.getExe watcher;
      Restart = "always";
      RestartSec = "3";
    };
  };
}

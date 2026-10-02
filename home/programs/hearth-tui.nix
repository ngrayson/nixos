# Hearth control TUI: dashboard + actions over the existing `ssh hearth`
# path (home/programs/ssh-hearth.nix). Workstation-only (Tawa/Theseus) —
# Hearth itself has no session to run a TUI in, and hearth-deploy already
# runs from here, not there.
#
# Every screen wraps an existing script (scripts/hearth-healthcheck.sh,
# hearth-disk, scripts/hearth-deploy.sh) instead of re-deriving its logic in
# Python, so the TUI can never drift from what those scripts actually gate.
#
# The home screen's go3 panel also reads the Go3 kiosk over the `go3` alias
# (home/programs/ssh-go3.nix): one read-only ssh round trip, no sudo.
{pkgs, ...}: let
  hearth-tui = pkgs.python3Packages.buildPythonApplication {
    pname = "hearth-tui";
    version = "0.1.0";
    pyproject = true;
    src = ./hearth-tui;
    build-system = [pkgs.python3Packages.setuptools];
    dependencies = [pkgs.python3Packages.textual];
  };
in {
  home.packages = [hearth-tui];
}

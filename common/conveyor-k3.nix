# Conveyor Personal Compute (VM runtime) prerequisites — import per host; Tawa only today.
# The conveyor-k3 CLI runs a Lima + QEMU guest that hosts Conveyor build pods. It needs Lima
# >= 2.2; the 26.05 pin has 2.1.3, so take it from nixpkgs-unstable rather than `nix flake
# update`. nixpkgs wraps limactl with QEMU on PATH, so no separate qemu package. Linger keeps
# the user-level `conveyor-k3-vm@<instance>` service running without a login session.
# The CLI itself is npm-installed (home/programs/conveyor-k3.nix): Conveyor's own update timer
# re-pins it. Decision record: documentation/conveyor-personal-compute.md.
{
  config,
  pkgs,
  unstablePkgs,
  ...
}: let
  # conveyor-k3 0.1.14 runs these host tools by absolute Debian/Ubuntu path
  # (dist/cli.js, dist/vm-qemu.js), and NixOS has only /usr/bin/env and /bin/sh
  # there: `vm setup` died at once with `spawn /usr/bin/which ENOENT`. Link
  # exactly the paths it calls, not envfs (which fakes all of /usr/bin for every
  # program). nc must be the OpenBSD netcat Ubuntu ships: QEMU guest forwards
  # run `nc -4 -n -w 60 <host> <port>`. Paths it uses only inside the guest
  # (k3s-uninstall.sh, cloudflared) are not needed here.
  systemd = config.systemd.package;
  fhsShims = {
    "/usr/bin/which" = "${pkgs.which}/bin/which";
    "/usr/bin/ssh" = "${pkgs.openssh}/bin/ssh";
    "/usr/bin/nc" = "${pkgs.netcat-openbsd}/bin/nc";
    "/usr/bin/stat" = "${pkgs.coreutils}/bin/stat";
    "/usr/bin/systemctl" = "${systemd}/bin/systemctl";
    "/usr/bin/loginctl" = "${systemd}/bin/loginctl";
    "/usr/bin/journalctl" = "${systemd}/bin/journalctl";
    "/bin/ps" = "${pkgs.procps}/bin/ps";
  };
in {
  nixpkgs.overlays = [
    (final: prev: {
      lima = unstablePkgs.lima;
    })
  ];

  environment.systemPackages = [pkgs.lima];

  systemd.tmpfiles.rules = map (path: "L+ ${path} - - - - ${fhsShims.${path}}") (builtins.attrNames fhsShims);

  users.users.wiz = {
    linger = true;
    extraGroups = ["kvm"];
  };
}

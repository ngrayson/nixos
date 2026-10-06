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
  #
  # `vm setup` also locates limactl, qemu-system-x86_64 and qemu-img with
  # `which` over a fixed PATH (~/.local/bin, /usr/local/bin, /usr/bin, ...),
  # never the NixOS one, and runs Lima with that same PATH (Lima then needs
  # ssh-keygen). UEFI firmware is looked up beside the QEMU binary, at
  # <qemu dir>/../share/qemu/edk2-x86_64-code.fd. The instance records the
  # paths it found in its state.json/lima.yaml, so they must stay stable:
  # they are Home Manager links in ~/.local (`force` because the first setup
  # ran against hand-made links of the same names). qemu_kvm is the
  # host-CPU-only QEMU build.
  localLinks = {
    ".local/bin/limactl" = "${pkgs.lima}/bin/limactl";
    ".local/bin/qemu-system-x86_64" = "${pkgs.qemu_kvm}/bin/qemu-system-x86_64";
    ".local/bin/qemu-img" = "${pkgs.qemu_kvm}/bin/qemu-img";
    ".local/bin/ssh-keygen" = "${pkgs.openssh}/bin/ssh-keygen";
    ".local/share/qemu/edk2-x86_64-code.fd" = "${pkgs.qemu_kvm}/share/qemu/edk2-x86_64-code.fd";
  };
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

  home-manager.users.wiz.home.file =
    builtins.mapAttrs (_: source: {
      inherit source;
      force = true;
    })
    localLinks;

  users.users.wiz = {
    linger = true;
    extraGroups = ["kvm"];
  };
}

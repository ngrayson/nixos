# Conveyor Personal Compute (VM runtime) prerequisites — import per host; Tawa only today.
# The conveyor-k3 CLI runs a Lima + QEMU guest that hosts Conveyor build pods. It needs Lima
# >= 2.2; the 26.05 pin has 2.1.3, so take it from nixpkgs-unstable rather than `nix flake
# update`. nixpkgs wraps limactl with QEMU on PATH, so no separate qemu package. Linger keeps
# the user-level `conveyor-k3-vm@<instance>` service running without a login session.
# The CLI itself is npm-installed (home/programs/conveyor-k3.nix): Conveyor's own update timer
# re-pins it. Decision record: documentation/conveyor-personal-compute.md.
{
  pkgs,
  unstablePkgs,
  ...
}: {
  nixpkgs.overlays = [
    (final: prev: {
      lima = unstablePkgs.lima;
    })
  ];

  environment.systemPackages = [pkgs.lima];

  users.users.wiz = {
    linger = true;
    extraGroups = ["kvm"];
  };
}

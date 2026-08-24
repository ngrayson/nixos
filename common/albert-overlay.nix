# Albert 34+ from nixos-unstable (bundled Firefox Python plugin).
# Used by profiles/workstation.nix and profiles/media-desktop.nix.
{unstablePkgs, ...}: {
  nixpkgs.overlays = [
    (final: prev: {
      albert = unstablePkgs.albert;
    })
  ];
}

# Root entrypoint (default for this repo on Tawa). For another machine, set e.g.
#   export NIXOS_CONFIG=$HOME/.config/nixos/hosts/<hostname>/configuration.nix
# before `nixos-rebuild`, or use a branch with a different root import.
{...}: {
  imports = [
    ./hosts/Tawa/configuration.nix
  ];
}

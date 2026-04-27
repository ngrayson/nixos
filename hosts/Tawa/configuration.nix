# Entry module for host Tawa. Build with:
#   nix build '<nixpkgs/nixos>' --attr config.system.build.toplevel --no-link \
#     --include nixos-config=/abs/path/to/hosts/Tawa/configuration.nix
# Or use repo root configuration.nix (imports this file) with the same nixos-config path.
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../common/system.nix
    ./hardware-configuration.nix
    ./host.nix
  ];
}

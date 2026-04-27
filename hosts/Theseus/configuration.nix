# Entry module for host Theseus (Framework laptop). Build with:
#   nix build '<nixpkgs/nixos>' --attr config.system.build.toplevel --no-link \
#     --include nixos-config=/abs/path/to/hosts/Theseus/configuration.nix
# Before first deploy on real hardware, replace ./hardware-configuration.nix with
# `nixos-generate-config` output (see file header there).
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

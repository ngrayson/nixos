{
  description = "NixOS configurations for Tawa, Theseus, and cloud hosts";

  inputs = {
    # Phase 1 migration: prove flake wiring on the same package family as the
    # running channel system before bumping to 26.05.
    # Exact revision used by Tawa generation 144.
    nixpkgs.url = "github:NixOS/nixpkgs/a4bf06618f0b";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    stylix = {
      url = "github:nix-community/stylix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    slippi-nix = {
      url = "github:lytedev/slippi-nix";
      flake = false;
    };

    vortix.url = "github:Harry-kp/vortix/fbd3b431e3372cdefb16a72920a809c865ba8029";
  };

  outputs = inputs @ {
    nixpkgs,
    home-manager,
    nixos-hardware,
    ...
  }: let
    system = "x86_64-linux";
    unstablePkgs = import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
    mkHost = modules:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs unstablePkgs;};
        modules =
          [
            home-manager.nixosModules.home-manager
          ]
          ++ modules;
      };
  in {
    nixosConfigurations = {
      Tawa = mkHost [
        ./hosts/Tawa/configuration.nix
      ];

      Theseus = mkHost [
        nixos-hardware.nixosModules.framework-amd-ai-300-series
        ./hosts/Theseus/configuration.nix
      ];
    };

    formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;
  };
}

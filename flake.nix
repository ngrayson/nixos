{
  description = "NixOS configurations for Tawa, Theseus, Hearth, Go3, and cloud hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Master tracks nixpkgs; follows our 26.05 pin. Lockfile holds the rev.
    sops-nix = {
      url = "github:Mic92/sops-nix";
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
  in rec {
    nixosConfigurations = {
      Tawa = mkHost [
        ./hosts/Tawa/configuration.nix
      ];

      Theseus = mkHost [
        nixos-hardware.nixosModules.framework-amd-ai-300-series
        ./hosts/Theseus/configuration.nix
      ];

      Hearth = mkHost [
        nixos-hardware.nixosModules.microsoft-surface-common
        ./hosts/Hearth/configuration.nix
      ];

      Go3 = mkHost [
        nixos-hardware.nixosModules.microsoft-surface-common
        ./hosts/Go3/configuration.nix
      ];

      Gcp = mkHost [
        ./hosts/Gcp/configuration.nix
      ];
    };

    formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;

    # Hostname-only evals, not toplevel. A full nixosSystem closure is too
    # heavy for 8 GB Conveyor codespaces; this still fails `nix flake check`
    # if any host module graph cannot evaluate.
    checks.${system} = let
      pkgs = nixpkgs.legacyPackages.${system};
      # Assert at eval time so `nix flake check --no-build` actually fails.
      checkHost = name: expected: let
        got = nixosConfigurations.${name}.config.networking.hostName;
      in
        assert nixpkgs.lib.assertMsg (got == expected)
        "nixosConfigurations.${name}.config.networking.hostName is '${got}', want '${expected}'";
          pkgs.runCommand "check-${name}-hostname" {} ''
            touch "$out"
          '';
    in {
      tawa-hostname = checkHost "Tawa" "Tawa";
      theseus-hostname = checkHost "Theseus" "Theseus";
      hearth-hostname = checkHost "Hearth" "Hearth";
      go3-hostname = checkHost "Go3" "Go3";
      gcp-hostname = checkHost "Gcp" "Gcp";

      # Nothing else in `checks` looks at style, so formatting drift survives
      # review and then taxes the next card that touches the file: on
      # 2026-09-01 `caddy.nix` and eleven other tracked files had fallen out of
      # alejandra, and reformatting the one block a card needed dragged an
      # unrelated hunk in with it. Unlike the hostname checks above this one
      # only parses the tree rather than evaluating a host closure, so the 8 GB
      # codespace constraint noted there does not apply.
      #
      # Scoped to `inputs.self`, which is git-tracked files only — the
      # gitignored per-widget `hosts/Hearth/intranet/config/*/config.nix` files
      # are deliberately outside it. `nix flake check --no-build` never builds
      # and so never runs this; `nix fmt -- --check .` gives the same answer
      # without a build.
      formatting =
        pkgs.runCommand "check-formatting" {
          nativeBuildInputs = [pkgs.alejandra];
        } ''
          alejandra --check ${inputs.self}
          touch "$out"
        '';
    };
  };
}

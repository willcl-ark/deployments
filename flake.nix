{
  description = "Server deployments";

  inputs = {
    nero-nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-26.05";
    };
    nero-disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nero-nixpkgs";
    };
    nero-will-nix = {
      url = "github:willcl-ark/nix/master";
      inputs.nixpkgs.follows = "nero-nixpkgs";
    };
    nero-b10c-nix = {
      url = "github:0xB10C/nix";
      inputs.nixpkgs.follows = "nero-nixpkgs";
    };
    nero-dnsseedrs = {
      url = "github:willcl-ark/dnsseedrs";
      flake = false;
    };
    nero-forgejo-src = {
      url = "github:willcl-ark/forgejo/full-mirror";
      flake = false;
    };
    nero-sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nero-nixpkgs";
    };
    nero-niks3 = {
      url = "github:Mic92/niks3";
      inputs.nixpkgs.follows = "nero-nixpkgs";
    };
    beelink-nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-25.11";
    };
    beelink-sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "beelink-nixpkgs";
    };
    fish-nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-25.11";
    };
    fish-disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "fish-nixpkgs";
    };
    fish-sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "fish-nixpkgs";
    };
    cdash-nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-26.05";
    };
    cdash-disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "cdash-nixpkgs";
    };
    cdash-will-nix = {
      url = "github:willcl-ark/nix";
      inputs.nixpkgs.follows = "cdash-nixpkgs";
    };
    cdash-sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "cdash-nixpkgs";
    };
    guix-nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-26.05";
    };
    guix-disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "guix-nixpkgs";
    };
    guix-will-nix = {
      url = "github:willcl-ark/nix";
      inputs.nixpkgs.follows = "guix-nixpkgs";
    };
    guix-sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "guix-nixpkgs";
    };
    fish-app-src = {
      url = "path:/home/will/src/fish.foo";
      flake = false;
    };
    bitcoin-core-ci.url = "github:willcl-ark/bitcoin-core-ci/da376218193e56a123d0c57014986ca2f0887cdf";
  };

  outputs = inputs:
    let
      hosts = import ./hosts.nix;
      toolPackages = builtins.listToAttrs (map (system: {
        name = system;
        value = inputs.nero-nixpkgs.legacyPackages.${system};
      }) [ "x86_64-linux" "aarch64-linux" ]);
      hostInputs = {
      nero = {
        nixpkgs = inputs.nero-nixpkgs;
        disko = inputs.nero-disko;
        will-nix = inputs.nero-will-nix;
        b10c-nix = inputs.nero-b10c-nix;
        dnsseedrs = inputs.nero-dnsseedrs;
        forgejo-src = inputs.nero-forgejo-src;
        sops-nix = inputs.nero-sops-nix;
        niks3 = inputs.nero-niks3;
      };
      beelink = {
        nixpkgs = inputs.beelink-nixpkgs;
        sops-nix = inputs.beelink-sops-nix;
        bitcoin-core-ci = inputs.bitcoin-core-ci;
      };
      fish = {
        nixpkgs = inputs.fish-nixpkgs;
        disko = inputs.fish-disko;
        fish-app-src = inputs.fish-app-src;
        sops-nix = inputs.fish-sops-nix;
      };
      cdash = {
        nixpkgs = inputs.cdash-nixpkgs;
        disko = inputs.cdash-disko;
        will-nix = inputs.cdash-will-nix;
        sops-nix = inputs.cdash-sops-nix;
      };
      guix = {
        nixpkgs = inputs.guix-nixpkgs;
        disko = inputs.guix-disko;
        will-nix = inputs.guix-will-nix;
        sops-nix = inputs.guix-sops-nix;
      };
      };
    in {
      deployments = hosts;
      nixosConfigurations = builtins.mapAttrs (name: host:
        hostInputs.${host.inputGroup}.nixpkgs.lib.nixosSystem {
          system = host.system;
          specialArgs.inputs = hostInputs.${host.inputGroup};
          modules = [ ./modules/common.nix (./hosts + "/${name}") ];
        }
      ) hosts;
      formatter = builtins.mapAttrs (_: pkgs: pkgs.nixfmt-tree) toolPackages;
      packages = builtins.mapAttrs (_: pkgs: {
        inherit (pkgs) nixos-anywhere;
      }) toolPackages;
      devShells = builtins.mapAttrs (_: pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            just jq nixos-rebuild nixos-anywhere openssh age sops ssh-to-age
          ];
        };
      }) toolPackages;
    };
}

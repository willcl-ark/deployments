{ inputs, pkgs, ... }:
let
  # The pinned shared module still uses the removed i2pd proto options.
  willNix = inputs.nixpkgs.legacyPackages.x86_64-linux.applyPatches {
    name = "will-nix-i2pd-settings";
    src = inputs.will-nix;
    patches = [ ./patches/i2pd-settings.patch ];
  };
in
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    "${willNix}/modules/bitcoin-dnsseed/nixos"
    inputs.will-nix.nixosModules.bitcoin-core-guix-substitutes
    inputs.will-nix.nixosModules.stuntman
    inputs.will-nix.nixosModules.forgejo-site
    inputs.will-nix.nixosModules.ralph
    inputs.will-nix.nixosModules.cli-proxy-api
    inputs.niks3.nixosModules.niks3
    inputs.b10c-nix.nixosModules.default.github-metadata-backup
    ./configuration.nix
  ];

  nixpkgs.overlays = [
    (_final: prev: {
      forgejo = prev.forgejo.overrideAttrs {
        src = inputs.forgejo-src;
        vendorHash = "sha256-cb6f7ZX3pG95EEZotGXn6+YUJN59SFNVHFTejFJ6y28=";
        doCheck = false;
        patches = (prev.forgejo.patches or []) ++ [
          ./patches/ralph-comments.patch
          ./patches/forgejo-github-metadata-api-read.patch
          ./patches/forgejo-github-metadata-sync-webhook.patch
          ./patches/forgejo-github-metadata-comment-edits.patch
          ./patches/forgejo-github-metadata-review-comment-map.patch
          ./patches/forgejo-github-metadata-pending-pull-sync.patch
          ./patches/forgejo-resource-index-sync.patch
        ];
        postPatch = ''
          ${prev.forgejo.postPatch}
          rm -rf vendor
        '';
      };
    })
  ];

  services.bitcoinDnsSeed.package = pkgs.callPackage inputs.dnsseedrs { };

}

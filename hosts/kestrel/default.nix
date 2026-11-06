{ inputs, ... }:
let
  host = import ./hosts/main.nix;
in
{
  imports = [
    inputs.disko.nixosModules.disko
    (inputs.cdash-src + "/modules/cdash/nixos")
    inputs.sops-nix.nixosModules.sops
    host.hardware.module
    ./disk-config.nix
    ./configuration.nix
    ./cdash.nix
  ];

  _module.args.host = host;
}

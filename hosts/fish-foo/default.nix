{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    ./disk-config.nix
    ./hardware-configuration.nix
    ./configuration.nix
  ];

  _module.args.settings = {
    hostName = "fish-foo";
    domain = "fish.foo";
    networkInterface = "enp1s0";
    ipAddress = "116.202.23.118";
    prefixLength = 32;
    gateway = "172.31.1.1";
  };
}

{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    ./disk-config.nix
    ./hardware-configuration.nix
    ./configuration.nix
  ];

  _module.args.fishSource = inputs.nixpkgs.lib.cleanSourceWith {
    src = inputs.fish-app-src;
    filter =
      path: _type:
      builtins.elem (builtins.baseNameOf path) [
        "server.py"
        "nero_watchdog.py"
        "nero_commands.py"
      ];
  };

  _module.args.settings = {
    hostName = "fish-foo";
    domain = "fish.foo";
    networkInterface = "enp1s0";
    ipAddress = "116.202.23.118";
    prefixLength = 32;
    gateway = "172.31.1.1";
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH988C5DbEPHfoCphoW23MWq9M6fmA4UTXREiZU0J7n0 will.hetzner@temp.com"
    ];
  };
}

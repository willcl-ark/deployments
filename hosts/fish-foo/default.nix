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
  };
}

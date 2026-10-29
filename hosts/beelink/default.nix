{ inputs, pkgs, ... }:
let
  # Keep job directories as Nix paths, matching the CI flake's store copies.
  ciSource = /. + builtins.unsafeDiscardStringContext inputs.bitcoin-core-ci.outPath;
  ciHome = "/var/lib/ci-runner";
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/ci-runner.nix
    inputs.sops-nix.nixosModules.sops
    (ciSource + "/jobs/bitcoin-core-nightly/module.nix")
    (ciSource + "/jobs/bitcoin-core-bench/module.nix")
    (ciSource + "/jobs/bitcoin-core-guix/module.nix")
    (ciSource + "/jobs/bitcoin-core-valgrind-fuzz/module.nix")
  ];

  _module.args = {
    system = "x86_64-linux";
    ci = {
      home = ciHome;
      queueDir = "${ciHome}/queue";
      workDir = "${ciHome}/work";
      flake = inputs.bitcoin-core-ci.outPath;
      bitcoinRepoUrl = "https://github.com/bitcoin/bitcoin";
      ctestSite = "willcl-ark/beelink";
      cdashBuildNamePrefix = "nixpkgs";
      ccache = {
        dir = "/var/cache/ci-runner/ccache";
        maxSize = "75G";
      };
      jobs = {
        nightly = ciSource + "/jobs/bitcoin-core-nightly";
        bench = ciSource + "/jobs/bitcoin-core-bench";
        guix = ciSource + "/jobs/bitcoin-core-guix";
        valgrindFuzz = ciSource + "/jobs/bitcoin-core-valgrind-fuzz";
      };
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = [ "msr" ];

  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "mode=1777"
      "size=32G"
    ];
  };

  networking.hostName = "beelink";
  networking.networkmanager = {
    enable = true;
    insertNameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };

  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";

  services.guix = {
    enable = true;
    package = pkgs.guix;
  };

  sops = {
    defaultSopsFile = ../../secrets/beelink/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH988C5DbEPHfoCphoW23MWq9M6fmA4UTXREiZU0J7n0 will.hetzner@temp.com"
  ];

  users.users.will = {
    isNormalUser = true;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH988C5DbEPHfoCphoW23MWq9M6fmA4UTXREiZU0J7n0 will.hetzner@temp.com"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  nix.settings = {
    trusted-users = [
      "root"
      "will"
      "ci-runner"
    ];
  };

  hardware.enableRedistributableFirmware = true;

  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  system.stateVersion = "25.11";
}

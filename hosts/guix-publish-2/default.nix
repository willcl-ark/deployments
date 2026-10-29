{
  config,
  inputs,
  options,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    inputs.will-nix.nixosModules.bitcoin-core-guix-substitutes
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "guix-publish-2";
  networking.useDHCP = true;

  boot.loader.grub = {
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH988C5DbEPHfoCphoW23MWq9M6fmA4UTXREiZU0J7n0 will.hetzner@temp.com"
    # Allows Nero to run `guix copy` to this publisher.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHEdZrzXxbJ7DhKaYH6GZpz0jdMsv7ajRI9VCVnELtg6 root@nero guix copy"
  ];

  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  # The existing 200 GiB ext4 volume is dedicated to the Guix store and
  # publisher state. It must not be reformatted by deployment.
  fileSystems."/gnu" = {
    device = "/dev/disk/by-uuid/cfd869ab-cbb1-4470-840d-3c185a6bee35";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  services.caddy.enable = true;

  services.guix.substituters.authorizedKeys =
    options.services.guix.substituters.authorizedKeys.default
    ++ [ ./nero-archive-key.pub ];

  services.bitcoinCoreGuixSubstitutes = {
    enable = true;
    domain = "guix2.fish.foo";

    signingKey = {
      publicFile = ../../secrets/guix-publish-2/signing-key.pub;
      privateFile = ../../secrets/guix-publish-2/signing-key.sec;
      signatureFile = ../../secrets/guix-publish-2/signing-key.pub.asc;
    };
  };

  networking.firewall.allowedTCPPorts = [
    22
    80
    443
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "25.11";
}

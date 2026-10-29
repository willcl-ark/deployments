{
  hostName = "cdash-server";
  domain = "cdash.fish.foo";
  # SSH destination. The OS gets its IPv4 address through DHCP below.
  address = "46.225.46.115";

  ssh = {
    installUser = "root";
    # Local private key path, used by the deployment commands only.
    identityFile = "~/.ssh/hetzner-temp";
    users.will = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH988C5DbEPHfoCphoW23MWq9M6fmA4UTXREiZU0J7n0 will.hetzner@temp.com"
    ];
  };
  kexecExtraFlags = "--kexec-syscall";

  system = "x86_64-linux";
  hardware = {
    disk = "/dev/sda";
    bootMode = "bios"; # "bios" or "uefi"
    module = ./main-hardware.nix;
  };

  # Native systemd-networkd settings allow DHCP or static addressing per host.
  network = {
    matchConfig.MACAddress = "92:00:0a:22:45:dc";
    networkConfig = {
      DHCP = "ipv4";
      Address = "2a01:4f8:1c1c:c7ee::1/64";
      Gateway = "fe80::1";
      IPv6AcceptRA = false;
    };
  };
}

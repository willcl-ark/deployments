{
  nero = {
    inputGroup = "nero";
    system = "x86_64-linux";
    target = "root@nero";
    port = 2222;
    all = true;
    install = {
      target = "root@nero";
      port = 22;
      keyType = "age";
      keyPath = "/var/lib/sops-nix/key.txt";
      recipient = "age1g695llyzvglytzpccdjst3zwlgjmtdvfr6q487hvstyhc4n4es6qn7lhsk";
    };
  };
  beelink = {
    inputGroup = "beelink";
    system = "x86_64-linux";
    target = "root@beelink";
    port = 22;
    all = true;
    # Its existing installation has no declarative disk layout.
    install = null;
  };
  fish-foo = {
    inputGroup = "fish";
    system = "x86_64-linux";
    target = "root@fish.foo";
    port = 22;
    all = true;
    install = {
      target = "root@fish.foo";
      port = 22;
      keyType = "age";
      keyPath = "/root/.config/sops/age/keys.txt";
      recipient = "age1uknwm3p5hp4fnmhmauj228qrvuf5rv9ntfx0ld06fp5jnpr6h4esc0s8gy";
    };
  };
  cdash-server = {
    inputGroup = "cdash";
    system = "x86_64-linux";
    target = "will@46.225.46.115";
    identity = "~/.ssh/hetzner-temp";
    port = 22;
    sudo = true;
    all = true;
    install = {
      target = "root@46.225.46.115";
      port = 22;
      keyType = "ssh";
      keyPath = "/etc/ssh/ssh_host_ed25519_key";
      recipient = "age1j36kwnp6lrpzzqkk6njsyd5a7hz8zjlwppz60x5s4rqs8f5p8pwsrd6m60";
      extraArgs = [
        "--kexec-extra-flags"
        "--kexec-syscall"
      ];
    };
  };
  guix-publish-2 = {
    inputGroup = "guix";
    system = "x86_64-linux";
    target = "root@guix-publish-2";
    port = 22;
    all = true;
    install = {
      target = "root@guix-publish-2";
      port = 22;
      keyType = "age";
      keyPath = "/var/lib/sops-nix/key.txt";
      recipient = "age1fa7qz7utypkq6zrh3gh2ps872570jxgx22mzmfqk7lre74r7faxsyutemv";
    };
  };
  guix-arm-builder = {
    inputGroup = "nero";
    system = "aarch64-linux";
    target = "root@arm-guix-builder";
    port = 22;
    identity = "~/.ssh/guix-builder-aarch64.pem";
    # Nero powers this host on only while it is needed for Guix builds.
    all = false;
    install = {
      target = "root@arm-guix-builder";
      port = 22;
    };
  };
}

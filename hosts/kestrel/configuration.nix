{ host, lib, ... }:

{
  boot.loader = if host.hardware.bootMode == "uefi" then {
    grub.enable = false;
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = false;
  } else {
    grub.enable = true;
  };

  assertions = [{
    assertion = builtins.elem host.hardware.bootMode [ "bios" "uefi" ];
    message = "hardware.bootMode must be bios or uefi";
  }];

  networking = {
    hostName = host.hostName;
    useNetworkd = true;
    useDHCP = false;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  systemd.network.networks."10-wan" = host.network;

  users.mutableUsers = false;
  users.users = {
    root.hashedPassword = "!";
    # Administration uses satoshi with sudo, not root SSH.
    root.openssh.authorizedKeys.keyFiles = [ ];
  } // lib.mapAttrs (_: keys: {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = keys;
  }) host.ssh.users;
  # Administrators authenticate with SSH keys and have no passwords.
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    settings = {
      PermitRootLogin = "no";
      AllowUsers = builtins.attrNames host.ssh.users;
      X11Forwarding = false;
    };
  };

  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
  };

  system.stateVersion = "26.05";
}

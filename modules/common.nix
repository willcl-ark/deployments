{ lib, pkgs, ... }:
{
  # Host modules can override these defaults with ordinary definitions.
  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_GB.UTF-8";

  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PasswordAuthentication = lib.mkDefault false;
      KbdInteractiveAuthentication = lib.mkDefault false;
      PermitRootLogin = lib.mkDefault "prohibit-password";
    };
  };

  users.users.root.openssh.authorizedKeys.keyFiles = lib.mkDefault [
    ../public-keys/will.pub
  ];

  nix.settings.experimental-features = lib.mkDefault [
    "nix-command"
    "flakes"
  ];

  # Host package lists add to these tools.
  environment.systemPackages = with pkgs; [
    git
    htop
    curl
    ghostty.terminfo
  ];
}

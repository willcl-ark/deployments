{ lib, ... }:
{
  # Host modules can override these defaults with ordinary definitions.
  services.openssh.enable = lib.mkDefault true;
  nix.settings.experimental-features = lib.mkDefault [
    "nix-command"
    "flakes"
  ];
}

{ lib, pkgs, ... }:
let
  artiConfig = (pkgs.formats.toml { }).generate "arti.toml" {
    proxy.socks_listen = "10.200.1.0:9150";
    storage = {
      cache_dir = "/var/cache/arti";
      state_dir = "/var/lib/arti";
      # The crawlers use an explicit address, so no discovery file is needed.
      port_info_file = "";
    };
  };

in
{
  # The shared seed module enables Tor alongside I2P; use Arti for onions here.
  services.tor.enable = lib.mkForce false;

  systemd.services.arti = {
    description = "Arti SOCKS proxy for DNS seed onion crawling";
    wantedBy = [ "multi-user.target" ];
    requires = [ "dnsseedrs-netns.service" ];
    after = [
      "dnsseedrs-netns.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.arti}/bin/arti proxy -c ${artiConfig}";
      # dnsseedrs disables onion crawling if its one-time startup probe fails.
      ExecStartPost = "${pkgs.curl}/bin/curl --silent --show-error --head --output /dev/null --socks5-hostname 10.200.1.0:9150 --max-time 60 --retry 4 --retry-all-errors --retry-delay 5 http://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/";
      TimeoutStartSec = "6min";
      DynamicUser = true;
      StateDirectory = "arti";
      StateDirectoryMode = "0700";
      CacheDirectory = "arti";
      CacheDirectoryMode = "0700";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = "10s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  systemd.services.dnsseedrs-mainnet = {
    requires = [ "arti.service" ];
    after = [ "arti.service" ];
  };
  systemd.services.dnsseedrs-signet = {
    requires = [ "arti.service" ];
    after = [ "arti.service" ];
  };
  systemd.services.dnsseedrs-testnet5 = {
    requires = [ "arti.service" ];
    after = [ "arti.service" ];
  };
}

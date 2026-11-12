{ pkgs, ... }:
let
  artiConfig = (pkgs.formats.toml { }).generate "arti.toml" {
    proxy.socks_listen = "10.200.1.0:9150";
    storage = {
      cache_dir = "/var/cache/arti";
      state_dir = "/var/lib/arti";
    };
  };

in
{
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
}

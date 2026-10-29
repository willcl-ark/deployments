{
  pkgs,
  config,
  settings,
  fishSource,
  ...
}:
let
  landing = import ./site.nix { inherit pkgs; };
  dnsMonitor = pkgs.fetchFromGitHub {
    owner = "willcl-ark";
    repo = "dns-monitor";
    rev = "7d51c81fcbf4d1b97cd712b589162f4cd016bba1";
    hash = "sha256-vwyDxMYqzxeW5bbW8QUq+UbAOjiTdsRlfQApE6eu5hQ=";
  };
  dnsMonitorPython = pkgs.python312.withPackages (pythonPackages: [
    pythonPackages.dnspython
    pythonPackages.fastapi
    pythonPackages.geoip2
    pythonPackages.uvicorn
  ]);
in
{
  imports = [ ./nero-downtime.nix ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;


  networking.hostName = settings.hostName;
  networking.useDHCP = false;
  networking.interfaces.${settings.networkInterface}.ipv4.addresses = [
    {
      address = settings.ipAddress;
      prefixLength = settings.prefixLength;
    }
  ];
  networking.defaultGateway = {
    address = settings.gateway;
    interface = settings.networkInterface;
  };
  networking.nameservers = [
    "1.1.1.1"
    "1.0.0.1"
  ];
  networking.firewall.allowedTCPPorts = [
    80
    443
    57996
  ];
  networking.firewall.allowedUDPPorts = [ 443 ];

  services.caddy = {
    enable = true;
    package = pkgs.callPackage ../../packages/caddy-cloudflare.nix { };
    virtualHosts = {
      ${settings.domain}.extraConfig = ''
        tls {
          dns cloudflare {env.CF_API_TOKEN}
        }
        root * ${landing}
        file_server
      '';
      "dns-monitor.${settings.domain}".extraConfig = ''
        tls {
          dns cloudflare {env.CF_API_TOKEN}
        }
        @probe {
          method POST
          path /api/probe
        }
        respond @probe 403
        reverse_proxy 127.0.0.1:8000
      '';
    };
  };

  sops.defaultSopsFile = ../../secrets/fish-foo/secrets.yaml;
  sops.age.keyFile = "/root/.config/sops/age/keys.txt";
  sops.secrets.caddy-cloudflare-token = { };
  sops.templates."caddy-env".content = ''
    CF_API_TOKEN=${config.sops.placeholder.caddy-cloudflare-token}
  '';

  systemd.services.caddy.serviceConfig.EnvironmentFile = config.sops.templates."caddy-env".path;

  users.groups.dns-monitor = { };
  users.users.dns-monitor = {
    isSystemUser = true;
    group = "dns-monitor";
  };

  systemd.services.dns-monitor = {
    description = "Bitcoin DNS seed monitor";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${dnsMonitorPython}/bin/python ${dnsMonitor}/main.py --db /var/lib/dns-monitor/monitor.db watch --interval 600";
      User = "dns-monitor";
      Group = "dns-monitor";
      StateDirectory = "dns-monitor";
      UMask = "0077";
      Restart = "always";
      RestartSec = "30s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];
    };
  };

  systemd.services.dns-monitor-web = {
    description = "Bitcoin DNS seed monitor web server";
    after = [
      "dns-monitor.service"
      "network-online.target"
    ];
    wants = [
      "dns-monitor.service"
      "network-online.target"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${dnsMonitorPython}/bin/python ${dnsMonitor}/serve.py --db /var/lib/dns-monitor/monitor.db --host 127.0.0.1 --port 8000";
      User = "dns-monitor";
      Group = "dns-monitor";
      StateDirectory = "dns-monitor";
      UMask = "0077";
      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];
    };
  };

  systemd.services.bitcoin-holepunch-rendezvous = {
    description = "Bitcoin TCP hole-punching rendezvous server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${fishSource}/server.py 57996";
      DynamicUser = true;
      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      CapabilityBoundingSet = "";
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];
    };
  };

  documentation.enable = false;
  fonts.fontconfig.enable = false;

  environment.systemPackages = with pkgs; [
    neovim
    age
  ];

  system.stateVersion = "25.11";
}

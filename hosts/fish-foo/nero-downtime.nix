{ config, pkgs, fishSource, ... }:
let
  commands = pkgs.runCommand "nero-telegram-commands" { } ''
    mkdir -p $out
    cp ${fishSource}/nero_watchdog.py $out/nero_watchdog.py
    cp ${fishSource}/nero_commands.py $out/nero_commands.py
  '';
in
{
  sops.secrets.nero-bot-token = { };

  systemd.services.nero-downtime = {
    description = "Check Nero public services and notify Telegram";
    after = [
      "network-online.target"
      "sops-install-secrets.service"
    ];
    wants = [
      "network-online.target"
      "sops-install-secrets.service"
    ];
    path = [
      pkgs.curl
      pkgs.dig
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${fishSource}/nero_watchdog.py";
      LoadCredential = "telegram-token:${config.sops.secrets.nero-bot-token.path}";
      DynamicUser = true;
      StateDirectory = "nero-downtime";
      UMask = "0077";
      TimeoutStartSec = "3min";
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
    };
  };

  systemd.services.nero-telegram-commands = {
    description = "Answer private Telegram queries about Nero availability";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "sops-install-secrets.service"
    ];
    wants = [
      "network-online.target"
      "sops-install-secrets.service"
    ];
    path = [
      pkgs.curl
      pkgs.dig
    ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${commands}/nero_commands.py";
      LoadCredential = "telegram-token:${config.sops.secrets.nero-bot-token.path}";
      DynamicUser = true;
      StateDirectory = "nero-telegram-commands";
      Restart = "on-failure";
      RestartSec = "5s";
      UMask = "0077";
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
    };
  };

  systemd.timers.nero-downtime = {
    description = "Check Nero every minute";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      AccuracySec = "1s";
    };
  };
}

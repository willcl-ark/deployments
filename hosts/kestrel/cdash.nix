{ config, host, lib, ... }:

{
  sops = {
    defaultSopsFile = ../../secrets/kestrel/default.sops.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = [ ];
    secrets.cdash-app-key.restartUnits = [ "cdash-init.service" ];
  };

  services.cdash = {
    enable = true;
    hostName = host.domain;
    appUrl = "https://${host.domain}";
    appKeyFile = config.sops.secrets.cdash-app-key.path;
    backupTimeframe = 90 * 24;
    mail.mailer = "log";
  };

  # Retain the source checkout's upload limits and submission timeouts.
  services.phpfpm.pools.cdash.phpOptions = lib.mkForce {
    variables_order = "EGPCS";
    upload_max_filesize = "192M";
    post_max_size = "256M";
  };
  # The CDash module uses nginx for PHP-FPM; Caddy handles public HTTPS.
  services.nginx.virtualHosts.${host.domain} = {
    listen = [ { addr = "127.0.0.1"; port = 8080; } ];
    extraConfig = "client_max_body_size 256m;";
    locations."= /index.php".extraConfig = lib.mkAfter ''
      fastcgi_read_timeout 2000s;
    '';
  };
  systemd.services.cdash-worker.serviceConfig.ExecStart = lib.mkForce (
    "${config.services.cdash.package.phpPackage}/bin/php -d variables_order=EGPCS "
    + "${config.services.cdash.dataDir}/app/artisan queue:work --timeout=2000 --max-time=3600 --memory=256"
  );

  # PHP-FPM's INI parser treats unquoted false and null as empty values.
  services.phpfpm.pools.cdash.phpEnv = lib.mkForce (
    lib.mapAttrs (_: value: builtins.toJSON value) (
      config.services.cdash.settings // {
        APP_BASE_PATH = "${config.services.cdash.dataDir}/app";
      }
    )
  );

  services.caddy = {
    enable = true;
    virtualHosts.${host.domain}.extraConfig = ''
      reverse_proxy 127.0.0.1:8080
    '';
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}

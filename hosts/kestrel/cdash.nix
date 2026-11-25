{ config, host, inputs, lib, pkgs, ... }:

{
  sops = {
    defaultSopsFile = ../../secrets/kestrel/default.sops.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = [ ];
    secrets.cdash-app-key.restartUnits = [ "cdash-init.service" ];
    secrets.cdash-smtp-password.restartUnits = [ "cdash-init.service" ];
  };

  # Let the CDash module supply plain phpEnv strings: NixOS already quotes them.
  # JSON-encoding them again puts literal quotes in APP_BASE_PATH, breaking
  # Laravel bootstrap with HTTP 500 even though CLI initialization succeeds.
  services.cdash = {
    enable = true;
    # Laravel ignores MAIL_ENCRYPTION; require TLS before SMTP authentication.
    # The frontend is built from the same fetched source inside the package, so
    # patch the source itself rather than the final derivation.
    package = (pkgs.callPackage (inputs.cdash-src + "/pkgs/cdash") {
      fetchFromGitHub = args: pkgs.applyPatches {
        name = "cdash-source-patched";
        src = pkgs.fetchFromGitHub args;
        patches = [ ./patches/cdash-test-output-download.patch ];
      };
    }).overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        substituteInPlace "$out/share/php/cdash/config/mail.php" \
          --replace-fail "'transport' => 'smtp'," "'transport' => 'smtp', 'require_tls' => true,"
        substituteInPlace "$out/share/php/cdash/config/session.php" \
          --replace-fail "'secure' => false," "'secure' => true,"
      '';
    });
    hostName = host.domain;
    appUrl = "https://${host.domain}";
    appKeyFile = config.sops.secrets.cdash-app-key.path;
    backupTimeframe = 90 * 24;
    mail = {
      mailer = "smtp";
      host = "smtp.mailbox.org";
      port = 587;
      encryption = "tls";
      user = "will@256k1.dev";
      fromAddress = "cdash@fish.foo";
      replyAddress = "cdash@fish.foo";
      passwordFile = config.sops.secrets.cdash-smtp-password.path;
    };
  };

  services.logrotate.settings.cdash = {
    files = [ "${config.services.cdash.dataDir}/app/storage/logs/cdash.log" ];
    frequency = "daily";
    rotate = 14;
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    # Keep the long-running queue worker's open log handle valid.
    copytruncate = true;
    su = "cdash cdash";
  };

  # Retain the source checkout's upload limits and submission timeouts.
  services.phpfpm.pools.cdash.phpOptions = lib.mkForce {
    variables_order = "EGPCS";
    upload_max_filesize = "192M";
    post_max_size = "256M";
    memory_limit = "512M";
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
    "${config.services.cdash.package.phpPackage}/bin/php -d variables_order=EGPCS -d memory_limit=1G "
    + "${config.services.cdash.dataDir}/app/artisan queue:work --timeout=2000 --max-time=3600 --memory=1024"
  );

  services.caddy = {
    enable = true;
    virtualHosts.${host.domain}.extraConfig = ''
      header Strict-Transport-Security "max-age=31536000"
      reverse_proxy 127.0.0.1:8080
    '';
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}

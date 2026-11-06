{
  config,
  lib,
  pkgs,
  ...
}:
{
  sops.secrets.nero-bot-token = {
    sopsFile = ../../secrets/kestrel/telegram.sops.yaml;
    restartUnits = [ "netdata.service" ];
  };
  sops.templates."netdata-telegram" = {
    owner = "netdata";
    mode = "0400";
    content = ''
      SEND_EMAIL="NO"
      SEND_TELEGRAM="YES"
      TELEGRAM_BOT_TOKEN="${config.sops.placeholder.nero-bot-token}"
      DEFAULT_RECIPIENT_TELEGRAM="448332502"
    '';
  };

  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "netdata";

  services.netdata = {
    enable = true;
    package = pkgs.netdata.override { withCloudUi = true; };
    enableAnalyticsReporting = false;
    config = {
      web."bind to" = "127.0.0.1";
      db = {
        "dbengine tier 0 retention size" = "256MiB";
        "dbengine tier 1 retention size" = "256MiB";
        "dbengine tier 2 retention size" = "256MiB";
      };
    };
    configDir = {
      "health_alarm_notify.conf" = config.sops.templates."netdata-telegram".path;
      "go.d/systemdunits.conf" = pkgs.writeText "cdash-systemdunits.conf" ''
        jobs:
          - name: cdash-services
            include:
              - postgresql.service
              - caddy.service
              - nginx.service
              - phpfpm-cdash.service
              - cdash-worker.service
      '';
      # Stock systemd unit alarms are disabled by default.
      "health.d/cdash-services.conf" = pkgs.writeText "cdash-service-alerts.conf" ''
        template: cdash_service_not_active
              on: systemd.service_unit_state
        chart labels: unit_name=postgresql caddy nginx phpfpm-cdash cdash-worker
            calc: $active
           units: state
           every: 10s
            crit: $this != nan AND $this == 0
           delay: up 1m down 1m
         summary: CDash service ''${label:unit_name} is not active
              to: sysadmin
      '';
      "health.d/disks.conf" = pkgs.writeText "kestrel-disk-alerts.conf" ''
        template: disk_space_usage
              on: disk.space
        chart labels: mount_point=/
            calc: $used * 100 / ($avail + $used)
           units: %
           every: 1m
            warn: $this > 80
            crit: $this > 90
           delay: up 1m down 15m
         summary: Disk ''${label:mount_point} space usage
              to: sysadmin

        template: disk_inode_usage
              on: disk.inodes
        chart labels: mount_point=/
            calc: $used * 100 / ($avail + $used)
           units: %
           every: 1m
            warn: $this > 80
            crit: $this > 90
           delay: up 1m down 15m
         summary: Disk ''${label:mount_point} inode usage
              to: sysadmin

        template: disk_fill_rate
              on: disk.space
        chart labels: mount_point=/
          lookup: min -10m at -50m unaligned of avail
            calc: ($this - $avail) / (($now - $after) / 3600)
           units: GB/hour
           every: 1m

        template: out_of_disk_space_time
              on: disk.space
        chart labels: mount_point=/
            calc: ($disk_fill_rate > 0) ? ($avail / $disk_fill_rate) : (inf)
           units: hours
           every: 10s
            warn: $this >= 0 and $this < 8
            crit: $this >= 0 and $this < 2
           delay: up 1m down 15m
         summary: Disk ''${label:mount_point} estimated time until full
              to: sysadmin
      '';
    };
  };

  systemd.services.netdata = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
    restartTriggers = [ config.sops.templates."netdata-telegram".content ];
  };
}

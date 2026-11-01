{
  config,
  lib,
  pkgs,
  ...
}:
let
  stateDir = config.services.ralph.stateDir;
  reportDir = config.services.ralph.reportDir;
  snapshotDir = "/var/lib/ralph-backup/sqlite";
  sourceDirs = [
    stateDir
    reportDir
  ];
in
{
  # Provision a private bucket and these secrets before importing this module.
  sops.secrets.ralph-backup-password.mode = "0400";
  sops.secrets.ralph-backup-environment.mode = "0400";

  services.restic.backups.ralph = {
    repository = "s3:https://edfc2e5212d83182dfa64fa22e3899ec.r2.cloudflarestorage.com/ralph-backups";
    passwordFile = config.sops.secrets.ralph-backup-password.path;
    environmentFile = config.sops.secrets.ralph-backup-environment.path;
    initialize = true;
    paths = sourceDirs ++ [ snapshotDir ];
    # SQLite snapshots live separately; never copy live databases or sidecars.
    exclude = lib.concatMap (directory: [
      "${directory}/**/*.sqlite"
      "${directory}/**/*.sqlite-wal"
      "${directory}/**/*.sqlite-shm"
      "${directory}/**/*.sqlite-journal"
      "${directory}/**/*.sqlite3"
      "${directory}/**/*.sqlite3-wal"
      "${directory}/**/*.sqlite3-shm"
      "${directory}/**/*.sqlite3-journal"
    ]) sourceDirs;
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
    pruneOpts = [
      "--keep-hourly 48"
      "--keep-daily 30"
      "--keep-weekly 12"
      "--keep-monthly 12"
    ];
    runCheck = true;
    backupPrepareCommand = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      umask 077
      rm -rf ${lib.escapeShellArg snapshotDir}
      mkdir -p ${lib.escapeShellArg snapshotDir}
      ${pkgs.findutils}/bin/find ${lib.escapeShellArgs sourceDirs} -type f \
        \( -name '*.sqlite3' -o -name '*.sqlite' \) -print0 \
        > /run/restic-backups-ralph/databases
      while IFS= read -r -d $'\0' database; do
        destination=${lib.escapeShellArg snapshotDir}"$database"
        mkdir -p "$(dirname "$destination")"
        (
          cd "$(dirname "$destination")"
          ${pkgs.sqlite}/bin/sqlite3 -readonly "$database" \
            '.timeout 30000' '.backup main snapshot.tmp'
          test "$(${pkgs.sqlite}/bin/sqlite3 -readonly snapshot.tmp 'PRAGMA quick_check;')" = ok
          mv snapshot.tmp "$destination"
        )
      done < /run/restic-backups-ralph/databases
    '';
  };

  systemd.services.restic-backups-ralph = {
    after = [ "sops-install-secrets.service" ];
    serviceConfig = {
      StateDirectory = "ralph-backup";
      StateDirectoryMode = "0700";
      UMask = "0077";
    };
  };
}

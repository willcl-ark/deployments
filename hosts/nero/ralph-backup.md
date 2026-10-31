# Ralph backups

Nero backs up Ralph state and public reports to the private Cloudflare R2
`ralph-backups` bucket using restic encryption and deduplication. The timer runs
hourly with up to five minutes of jitter. Retention keeps 48 hourly, 30 daily,
12 weekly and 12 monthly snapshots. Each run checks repository metadata.

The SOPS keys in `secrets/nero/secrets.yaml` are `ralph-backup-password` and
`ralph-backup-environment`. The latter contains `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY` and `AWS_DEFAULT_REGION=auto`. Credentials grant object
read/write access only to this bucket. Keep the encryption password recoverable
outside Nero. Bucket access without that password cannot recover the reviews.

All state, reports, private traces and retained Git objects are included.
SQLite databases use online snapshots under `/var/lib/ralph-backup/sqlite`,
followed by their original absolute paths. Live database files and their
WAL/SHM/journal files are excluded. Snapshots are consistent per database, not
one atomic snapshot across all databases and reports.

Check `restic-backups-ralph.service` and `restic-backups-ralph.timer` with
systemctl, and inspect the service journal after failures. A running timer alone
does not prove a successful recent backup. The generated `restic-ralph` wrapper
provides the repository credentials for manual snapshot and recovery commands.
Run it as root; never print the environment/password files.

## Recovery

Restore into an empty directory first using `restic-ralph restore SNAPSHOT
--target DIRECTORY`. Verify the restored database snapshots with SQLite
`PRAGMA quick_check` and inspect a historical report before using the restore.

Stop Ralph, Telegram, stats and follow-up writers and their timers before
replacing live data. Restore state and reports to their configured paths. Copy
each database from the restored `var/lib/ralph-backup/sqlite/<original path>`
back to its original location. Remove obsolete WAL/SHM/journal sidecars before
opening restored databases and restore service-user ownership.

A historical jobs database can replay work or remote writes that occurred after
its snapshot. Reconcile queue and publication state before restarting workers.
Keep the pre-recovery data until the recovered service is verified. Restic
retention protects historical snapshots from routine pruning; the writer's R2
credentials can still delete repository objects, so it does not provide an
immutable copy against host compromise.

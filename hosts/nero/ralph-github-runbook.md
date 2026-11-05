# Ralph GitHub cutover commands

Use this runbook for Nero after the migration package and host configuration are
ready. This covers both `bitcoin/bitcoin` and `bitcoin-core/gui-qml`.

The sequence is stop, back up, switch, migrate, restart. Activity while ingestion
is stopped may be missed, as agreed. The database migration preserves review
history and queued work; this guide does not delete either. Existing report URLs
and Forgejo links remain valid while the mirror stays available.

Run one numbered step at a time. Stop on unexpected errors. Commands marked
**workstation** run in `/home/will/deployments`. Commands marked **Nero** run in a
root Bash session opened with `ssh -p 2222 root@nero`. Keep that session open so
its variables survive between steps. No command in this document has been run
against the live host as part of writing it.

## 1. Prepare the release before stopping anything

The deployment repository must already contain all of these changes:

- `nero-will-nix` pinned to the published migration revision, including the fix
  for sweeps stalling on tied timestamps identified in the final review.
- Both repositories use GitHub origins and `repositoryUrl`; removed Forgejo
  options are gone. Keep repository IDs `core` and `gui` and existing state/report
  directories.
- Both use `githubPublication = "full"`; Core has `commentCollapsed = true`.
- Both webhook secrets exist in SOPS, readable by `ralph`.
- Caddy forwards the two paths below unchanged to `127.0.0.1:8765`.

At the time this guide was written, the host files still used Forgejo settings.
Preparing and publishing those configuration changes is a prerequisite, not
something `--migrate-github` does.

**Workstation:**

```sh
cd /home/will/deployments
git status --short
just build nero
just --dry-run switch-remote-nero
```

Do not continue if the build fails or the preview targets an unexpected host.
Do not use `just deploy`: that is a destructive first installation.

## 2. Prepare the GitHub webhooks, leaving them inactive

In each repository's Settings → Webhooks, create or edit:

| Repository | Payload URL |
| --- | --- |
| `bitcoin/bitcoin` | `https://review.fish.foo/webhooks/bitcoin/bitcoin` |
| `bitcoin-core/gui-qml` | `https://review.fish.foo/webhooks/bitcoin-core/gui-qml` |

Use `application/json`, SSL verification enabled, the corresponding SOPS secret,
and **Pull requests** only. Leave **Active** unchecked until step 8. An initial
ping before the new routes are live may fail; redeliver it after activation.
These are manual GitHub settings, not shell commands.

## 3. Stop and hold all Ralph writers

Disable the two old Ralph webhooks in Forgejo's settings. Leave Forgejo itself
and the metadata-mirror services running.

**Workstation:**

```sh
ssh -p 2222 root@nero
```

**Nero:**

```sh
set -euo pipefail
ralph_state=/var/lib/forgejo-review-bot
ralph_old_system=$(readlink -f /run/current-system)
ralph_old_bin=$(sed -nE 's|^ExecStart=([^ ]*/bin/ralph-service).*|\1|p' /etc/systemd/system/ralph.service)
ralph_old_registry=$(sed -nE 's|.*(/nix/store/[^ /]+-ralph-repositories.json).*|\1|p' /etc/systemd/system/ralph.service)
test -x "$ralph_old_bin"
test -f "$ralph_old_registry"
printf '%s\n' "$ralph_old_system" > /root/ralph-pre-github-system

test ! -e /run/ralph-cutover-start-allowed
for unit in ralph.service ralph-telegram.service ralph-followup.service \
  ralph-stats.service ralph-followup.timer ralph-stats.timer; do
  mkdir -p "/run/systemd/system/$unit.d"
  test ! -e "/run/systemd/system/$unit.d/90-ralph-cutover.conf"
  printf '[Unit]\nConditionPathExists=/run/ralph-cutover-start-allowed\n' \
    > "/run/systemd/system/$unit.d/90-ralph-cutover.conf"
done
systemctl daemon-reload
systemctl stop ralph-followup.timer ralph-stats.timer
systemctl stop ralph-telegram.service ralph-followup.service ralph-stats.service
systemctl stop ralph.service
systemctl show -p Id -p ActiveState ralph.service ralph-telegram.service \
  ralph-followup.service ralph-stats.service
```

Expect all four services to be inactive. Ralph's normal stop drains active reviews
and has no timeout; it may take a while. This guide does not force-kill an active
publication. The temporary start conditions prevent activation from starting the writers before
migration. Leave the marker file absent. Do not reboot during the procedure:
these runtime drop-ins disappear on reboot.

List held deliveries using the old package and registry:

```sh
runuser -u ralph -- "$ralph_old_bin" \
  --state-dir "$ralph_state" --repositories "$ralph_old_registry" \
  --list-held-deliveries
```

Expect `[]`. If there are holds, stop here and reconcile them using the old
service before cutover. To restart the old service, first remove the temporary
start guards using the removal loop in step 8. Do not clear holds just to get
migration to proceed: an
uncertain request may already have posted a comment.

## 4. Back up the stopped state

**Nero:**

```sh
systemctl start restic-backups-ralph.service
systemctl show -p Result -p ExecMainStatus restic-backups-ralph.service
restic-ralph snapshots --latest 1
```

Require `Result=success`, `ExecMainStatus=0`, and a fresh snapshot. The service's
prepare hook makes SQLite-consistent copies; merely running `restic snapshots`
does not make a backup. Keep the snapshot ID with your cutover notes.

## 5. Prepare Git checkouts

The old Core stores were partial clones. Replace them with complete stores before
using code that removes `--refetch`. Keep the old stores for rollback.

**Nero:**

```sh
runuser -u ralph -- bash <<'BASH'
set -euo pipefail
cd /var/lib/forgejo-review-bot
for d in checkout followup/checkout; do
  test -d "$d"
  test ! -e "$d.pre-github"
  mv "$d" "$d.pre-github"
  git init -q "$d"
  git -C "$d" remote add origin https://github.com/bitcoin/bitcoin.git
  git -C "$d" fetch --no-tags origin +refs/heads/master:refs/ralph/seed/master
done
for d in repos/gui/checkout followup/repos/gui/checkout; do
  git -C "$d" remote get-url origin > "$d.pre-github-origin"
  git -C "$d" remote set-url origin https://github.com/bitcoin-core/gui-qml.git
  git -C "$d" rev-list --objects --all --missing=print > "$d.github-object-check"
  if grep -q '^?' "$d.github-object-check"; then
    echo "Missing objects in $d; hydrate or replace it before proceeding." >&2
    exit 1
  fi
done
BASH
```

The seed ref retains Core's master history. If a checkout is absent or any command
fails, inspect and finish that checkout manually before proceeding; do not rerun
the whole block over already-moved directories. The GUI checks assume its existing
stores are complete. No tokens belong in Git remote URLs.

## 6. Switch the prepared host configuration

Keep the root session from step 3 open. In a second terminal, **workstation**:

```sh
cd /home/will/deployments
just switch-remote nero
```

This activates the prepared configuration, including Caddy and SOPS. The temporary start
conditions must remain in place. If activation reports an error, inspect it before
proceeding; do not assume a partial switch succeeded.

Back in the original **Nero** session:

```sh
test ! -e /run/ralph-cutover-start-allowed
systemctl show -p Id -p Conditions ralph.service ralph-telegram.service \
  ralph-followup.service ralph-stats.service \
  ralph-followup.timer ralph-stats.timer
systemctl show -p Id -p ActiveState ralph.service ralph-telegram.service \
  ralph-followup.service ralph-stats.service
ralph_new_bin=$(sed -nE 's|^ExecStart=([^ ]*/bin/ralph-service).*|\1|p' /etc/systemd/system/ralph.service)
ralph_new_registry=$(sed -nE 's|.*(/nix/store/[^ /]+-ralph-repositories.json).*|\1|p' /etc/systemd/system/ralph.service)
test -x "$ralph_new_bin"
test -f "$ralph_new_registry"
"$ralph_new_bin" --help
cat "$ralph_new_registry"
```

Require all six units to retain the cutover condition and the four services to be
inactive. Check that help
lists `--migrate-github`, and that the registry has GitHub origins/URLs for both
repositories, correct publication modes, and no Forgejo API settings. The registry
contains credential paths, not credential contents. Reading `/etc` directly here
selects the unit installed by the new system.

## 7. Migrate the database

**Nero:**

```sh
runuser -u ralph -- "$ralph_new_bin" \
  --state-dir "$ralph_state" --repositories "$ralph_new_registry" \
  --migrate-github
ls -l "$ralph_state/jobs.sqlite3.pre-github.bak"
runuser -u ralph -- "$ralph_new_bin" \
  --state-dir "$ralph_state" --repositories "$ralph_new_registry" \
  --list-held-deliveries
```

Expect `GitHub migration complete`, the backup file, and `[]`. `already migrated`
is expected only when deliberately repeating a successful migration. If migration
fails, leave the start guards in place and inspect the error; do not delete its backup
or the database blindly.

This rewrites stored source identities and review-scope URLs, preserving history
and pending work. It does not rewrite published reports or translate Forgejo
comment IDs into GitHub IDs. The initial sweep starts at migration time; activity
during the earlier outage may be missed. That is accepted for this cutover.

## 8. Restart and enable GitHub ingestion

**Nero:**

```sh
for unit in ralph.service ralph-telegram.service ralph-followup.service \
  ralph-stats.service ralph-followup.timer ralph-stats.timer; do
  rm "/run/systemd/system/$unit.d/90-ralph-cutover.conf"
done
systemctl daemon-reload
systemctl reset-failed ralph.service
systemctl start ralph.service
systemctl is-active ralph.service
journalctl -u ralph.service --since '5 minutes ago' --no-pager
```

Require successful startup and no restart loop or repository-identity errors.
The existing proxy authentication readiness condition must still be satisfied.
Then activate both GitHub hooks in the browser and redeliver their `ping` events;
require HTTP **202** for each.

**Nero:**

```sh
systemctl start ralph-telegram.service
systemctl start ralph-followup.timer ralph-stats.timer
systemctl is-active ralph.service ralph-telegram.service \
  ralph-followup.timer ralph-stats.timer
systemctl list-timers ralph-followup.timer ralph-stats.timer
```

Persistent timers can run immediately. Pending jobs can also resume immediately;
there is no guarantee of an empty queue. Use Telegram `/review` for any particular
PR missed during the outage.

## 9. Verify the first real review

**Nero:**

```sh
journalctl -u ralph.service --since '15 minutes ago' --no-pager
runuser -u ralph -- "$ralph_new_bin" \
  --state-dir "$ralph_state" --repositories "$ralph_new_registry" \
  --list-held-deliveries
systemctl is-active forgejo.service
systemctl list-timers 'github-metadata-backup*'
```

Check a real opened/reopened/pushed PR delivery returns 202 and logs a matching
repository and PR number. Verify one GitHub comment, collapsed for Core and
expanded for GUI, a working report link and Telegram notification. On a later
review, check previous findings still appear in review memory. Leave the old
Forgejo Ralph hooks disabled; leave mirror syncing enabled.

## If something fails

Keep or restore the temporary start conditions and stop the four writers before touching state.
The old system path is in `/root/ralph-pre-github-system`, the database backup is
`jobs.sqlite3.pre-github.bak`, Core's old stores end in `.pre-github`, and GUI's
old origin URLs are in the `.pre-github-origin` files. The restic snapshot includes
other state and reports.

A rollback after new GitHub comments have been published needs delivery
reconciliation; simply restoring an old database can repeat writes. Read the
[backup restore notes](ralph-backup.md) before restoring. Prefer fixing forward
for a small configuration error. Do not delete the old stores or backups until
the cutover has been checked and the soak period is complete.

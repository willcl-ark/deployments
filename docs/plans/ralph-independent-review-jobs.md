# Independent Ralph review jobs

Status: implementation plan, not implemented.

## Outcome and scope

A normal NixOS switch restarts the coordinator promptly without waiting for
reviews. Already-running reviews finish using their original package and
configuration. Newly admitted jobs use the newly deployed package. Existing
jobs count against the same global and per-repository concurrency limits: an
upgrade does not create extra capacity. If every slot is occupied, new work
still waits for a slot.

Keep one coordinator, the existing SQLite queue, and the existing review,
verification, publication and retry flow. No message broker, containers,
checkpoint/resume framework, or alternate threaded-worker mode. Changes belong
in /home/will/src/nix; deployments only receives the validated input pin.

Acceptance target: with a deliberately blocked test review running, coordinator
restart completes within 10 seconds and a normal switch does not wait for that
review. This excludes evaluation/build time and unrelated services. A queued
job starts under the new package when capacity permits; the old review retains
its PID, package, claim and ability to finish.

## Current constraints

- coordinator.py starts worker threads and holds the coordinator singleton lock.
- service.py:process_job owns acquisition, inference, durable results,
  publication and completion. Reuse it inside a standalone process.
- jobs.py:claim already applies global/per-repository admission transactionally
  and prevents simultaneous running reviews for one PR.
- jobs.py:recover currently releases every running claim at startup. It cannot
  run unchanged while independent workers survive coordinator restarts.
- service.py:CHECKOUT_LOCK is a thread lock. Replace it with a per-repository
  file lock covering the same checkout mutations and reads.
- Ralph experiment serialization uses a per-UID lock in /tmp. Independent
  PrivateTmp namespaces would defeat it. Put that lock in explicitly shared
  service state and preserve its existing concurrency policy.
- The usage ledger records spending; do not describe it as a budget reservation
  system or add a new budgeting subsystem as part of this change.

## Process and systemd design

Keep ralph.service as the short-lived ingestion/scheduling coordinator.
Launch one independently supervised transient service per admitted attempt,
with a deterministic name derived from repository, job ID and claim token.
Use a service, not a scope tied to the launching process. No PartOf or BindsTo
relationship to ralph.service; no automatic worker restart by systemd. The
queue remains the single authority for retry decisions.

Preferred first implementation: launch transient user services through the
Ralph account's lingering systemd user manager. This avoids granting the
coordinator arbitrary permission to create root system services. Keep the
coordinator a system service and explicitly configure its user-bus connection
and ordering on user@UID.service. Set the job executable to the exact Nix store
path, never a mutable current-package symlink.

First prove this arrangement in a NixOS VM. Verify the dedicated account's user
manager survives coordinator restart and ordinary activation, can read required
credentials, and supports the filesystem protections and experiment cgroup
setup. User units do not inherit the coordinator's sandbox. Recreate and test
the relevant isolation explicitly. If this cannot preserve required isolation,
stop and revise the launch design to a narrowly constrained system-level
launcher; do not silently drop protections or grant broad StartTransientUnit
access. This is the main deployment-mechanism decision to resolve before
production implementation.

Each job needs its own delegated experiment cgroup. The current module targets
/sys/fs/cgroup/system.slice/ralph.service; workers must not continue using the
coordinator's cgroup. Move experiment permissions and writable cgroup access to
the worker arrangement. This is a specific acceptance gate for the user-manager
prototype. A fixed system-level ralph-job@.service template with narrowly scoped
polkit start/stop permission is the alternative to evaluate if delegation or
sandboxing fails; test template updates do not restart existing instances.

## Durable attempt ownership

Persist the unit name, claim token, package path and a non-secret configuration
snapshot/reference for each attempt. Tokens remain the authority for writes.
Create a protected per-attempt directory and a GC root for the package closure
before launch. Pin prompt/profile settings, engine identity, repository context
and publication policy. Keep credentials out of argv, journals, SQLite and the
Nix store. Define how the job obtains credentials at startup; token revocation
can still interrupt an old job and should use the existing retry path.

Dispatch sequence:

1. Claim capacity and persist the intended unit identity transactionally.
2. Atomically write the attempt manifest and establish its package GC root.
3. Ask systemd to start that exact unit; wait only for launch acknowledgement.
4. The worker loads its own claim, validates its token and runs one attempt.
5. The worker persists its result and publication/completion state using the
   existing token-checked methods, then exits.
6. Reconciliation releases attempt artifacts and GC roots only after the unit
   is definitively stopped and durable state has been reconciled.

SQLite and systemd cannot share a transaction. Treat uncertain launch results
as reconciliation work, never immediate permission to launch a second attempt.
An existing unit with the expected identity is adopted, not restarted. Unit
names include attempt tokens to prevent collisions with later retries.

On coordinator startup and periodically thereafter, reconcile running claims
against exact systemd units. Preserve activating, active and deactivating
attempts. If systemd cannot be queried, pause new admission/recovery rather
than assuming workers are dead. Reclaim only after confirmed absence or exit;
retain existing result-aware publication retry behavior. Reconcile orphaned
units and manifests conservatively without deleting another live attempt.

Explicitly handle crashes before manifest creation, before start submission,
after successful start but before acknowledgement, during execution, after
result persistence and after publication but before completion recording.
Remote publication is not an exactly-once transaction; preserve existing
idempotency/reconciliation behavior and test ambiguous publication outcomes.

## Worker extraction and coordinator shutdown

Extract the body of one worker iteration into a standalone job entry point.
Reuse repository-context loading instead of duplicating it. The job runs the
whole process_job lifecycle, including publication, so it does not depend on a
live coordinator to finish. Its engine remains pinned even if the coordinator
restarts with different defaults.

The coordinator keeps webhook ingestion, command processing, fair scheduling
and reconciliation. Retain its singleton lock. Replace worker threads with
bounded launch/reconciliation work; no thread may wait for review completion.
On SIGTERM, stop admission, finish or safely abandon bounded launch operations,
close ingestion and release the coordinator lock. Bound network operations in
command/launch paths so they cannot recreate an hour-long shutdown. Give the
coordinator a finite stop timeout; killing it must leave recoverable claims.

Workers retain stale-head/generation checks. Keep one running attempt per PR
until the old unit has exited, even when it becomes superseded. Cancellation
must invalidate the claim and stop the complete worker cgroup, including
experiments, before reclaiming its execution slot. Coordinator replacement is
not worker cancellation. Reboot and explicit emergency cancellation may lose
unfinished inference and use existing job retry behavior.

## Atomic implementation commits

1. Extract the one-attempt runner and reusable context loading. Preserve
   existing processing behavior. Add the installed job executable.
2. Replace checkout and experiment locks with shared process-safe locks. Test
   actual overlapping processes against one repository and experiment limit.
3. Add durable attempt identity and exact-unit reconciliation. Replace blanket
   running-claim recovery. Cover interrupted dispatch and retained results.
4. Add the systemd launch adapter and Nix account/user-manager configuration.
   Pin execution configuration and package closure; preserve service isolation.
5. Switch coordinator scheduling to independent jobs and remove threaded
   execution/drain behavior. No runtime compatibility switch. Add operator
   status/cancellation commands and document lifecycle and failure semantics.

These commits form one release. Do not deploy intermediate states.

## Verification

Extend existing queue/coordinator/service tests rather than adding parallel
implementations of their behavior. High-value checks:

- Restart during a live job preserves its token and does not repeat inference.
- Old and new package jobs overlap while sharing admission limits and PR locks.
- Crash at dispatch boundaries cannot duplicate execution or strand capacity.
- Worker failure/reboot recovers correctly; stored results retry publication
  without inference. Unknown systemd state does not reclaim live work.
- Supersession/cancellation prevents stale publication and kills experiments.
- Checkout and experiment serialization hold across real processes.
- Manifest/configuration is pinned, secrets are absent from public metadata,
  and GC cannot remove an active job's package.

Use a NixOS VM with a fake worker and fake publication endpoint for the actual
systemd/activation test. Hold an old-version job at a barrier, switch to a new
version, verify unchanged PID and old package, then start a new-version job in
another available slot. Release both and verify results, unit cleanup and GC
roots. Repeat with coordinator death during dispatch and with reboot recovery.
No paid model calls or real GitHub writes in tests.

Run package tests, Nix formatting/evaluation, ralph and ralph-service builds,
and the VM lifecycle test. Python unit tests alone cannot prove the lifetime
and permission properties of systemd services.

## Cutover, schema policy and rollback

The first deployment still needs one final drain of the legacy threaded
coordinator, or an explicitly approved cancel/retry. Running Python threads
cannot be transferred into the new job units. Once drained, migrate state and
start the new coordinator. Remove the old execution path in the same release.

Separate database initialization/migration from worker opening. JobStore
construction currently performs migrations, including unfinished engine identity
updates; an old worker must not run migrations against newer coordinator state.

Normal later releases may overlap only while their shared queue/manifest/result
formats remain compatible. This is an active-job protocol requirement, not a
legacy execution mode. A breaking schema or publication-policy change requires
an explicit maintenance drain or cancellation before migration. Do not migrate
in place while an incompatible worker is alive.

Rollback must respect the same rule. Never restart the old threaded coordinator
against live independent jobs: its blanket recovery would invalidate them.
Stop new admission, drain/cancel the independent jobs, then perform a verified
state-compatible rollback or forward fix. Do not restore an old database over
already-published results.

Deploy with the usual publish/pin/switch workflow. Verify coordinator health,
job unit survival, queue progress, timers, publication outcomes and failed units.
Document that a coordinator-only restart differs from stopping all Ralph jobs.

## Sources

- /home/will/src/nix/pkgs/ralph-service/ralph_service/service.py
- /home/will/src/nix/pkgs/ralph-service/ralph_service/coordinator.py
- /home/will/src/nix/pkgs/ralph-service/ralph_service/jobs.py
- /home/will/src/nix/modules/ralph/nixos/default.nix
- https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html
- https://www.freedesktop.org/software/systemd/man/257/loginctl.html
- https://wiki.nixos.org/wiki/Systemd/User_Services

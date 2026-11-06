# Server deployments

This flake is the deployment entry point for Nero, Beelink, fish.foo, Kestrel for CDash,
Guix publish and the on-demand ARM Guix builder. Server configurations share a
pinned `nixos-unstable` and SOPS-Nix. Other service modules retain their existing
independent pins. Deployment commands are explicit per-host just recipes.

```sh
nix develop
just hosts
just --dry-run switch-all
just check
just build nero
just switch nero
just switch beelink
just switch all
just switch-remote nero
```

`switch` evaluates locally, builds on the target, and activates there with
`nixos-rebuild`. CDash on Kestrel uses `satoshi` with sudo; the other machines use root.
It does not synchronize or overwrite `/etc/nixos`. Run future deployments here.
SSH aliases and identities come from your SSH configuration, with Nero's port
2222 and the ARM identity path set in their just recipes. Kestrel uses the
`kestrel` SSH alias and its configured identity, with `satoshi` for updates.

`switch-remote HOST` rsyncs the working tree into `/var/lib/nixos-deployments`
and runs `nixos-rebuild` there over SSH. Evaluation, dependency downloads,
compilation and activation all happen on the server, reducing laptop traffic.
The sync includes uncommitted edits, excludes `.git` and gitignored files, and
deletes stale files from that dedicated directory. It leaves `/etc/nixos` alone.
CDash uses sudo for both the sync and rebuild. No lock pins are updated.

`switch-remote all` currently covers Nero, Beelink, CDash and guix-publish-2.
Use `switch-remote guix-arm-builder` explicitly when ARM is running. Remote
switching for fish.foo is deferred until its local application input is
published; use the existing `switch fish-foo` meanwhile. Preview the commands
with `just --dry-run switch-remote-all` or `just --dry-run switch-remote-nero`.

`switch all` updates the five always-on hosts sequentially and stops on the
first error. It does not roll back hosts already updated. The ARM builder is
normally powered off; update it explicitly with `just switch guix-arm-builder`
when it is running. `check` includes ARM. Local ARM builds
need an aarch64 builder or emulation.

`just --dry-run switch-nero` prints the command without connecting. Use the
per-host recipe name for previews; `just --dry-run switch nero` only prints the
call to that recipe. `check` checks the flake and evaluates system derivations
without building them. `build HOST` builds locally without activation.
Commands require a current lock file and do not update pins automatically.

Both Nero switch recipes acquire the same local lock before syncing or building.
Repeated invocations from this user on this workstation wait for the preceding
one, including across repository checkouts. They also wait for a remote activation
that survived an interrupted SSH connection or started before locking was added.
The lock is held through activation, including Ralph's review drain. Waiting
commands use the working tree as it exists when they acquire the lock.
Deployments from other workstations or direct nixos-rebuild commands are not
covered; coordinate those separately.


## Layout

- `flake.nix`, `flake.lock`: host construction and pinned dependencies.
- `hosts.nix`: host architectures and service input groups.
- `justfile`: deployment targets, SSH settings and commands.
- `hosts/<name>/`: hardware, networking and service configuration.
- `packages/`: shared package definitions, currently Caddy with Cloudflare DNS.
- `modules/common.nix`: shared defaults, overridable by host definitions.
- `public-keys/will.pub`: admin SSH public key shared by all hosts.
- `modules/ci-runner.nix`: CI queue runner service and its account/directories.
- `modules/dnsseed.nix`: Nero's DNS seed and Caddy configuration.
- `secrets/<host>/`: encrypted files and public signatures.
- `.sops.yaml`: recipient rules scoped to those paths.

The common module sets UTC, `en_GB.UTF-8`, SSH key authentication, flakes and
the shared tools: Git, htop, curl and Ghostty terminfo. It grants the admin key
root access by default. CDash instead grants that same key to `satoshi` with sudo
and disables root SSH. ARM retains its separate builder key as well.

Add settings or tools in `modules/common.nix` to apply them everywhere. Host
package lists add to the shared list. Ordinary host settings override the
common `lib.mkDefault` values, for example `time.timeZone = "Europe/London";`.
Editors, service packages, users, network configuration and SSH port exceptions
remain in host files. Keep `system.stateVersion` at its existing value when
changing nixpkgs.

Beelink imports application code from the pinned `bitcoin-core-ci` input. Its
runtime CI jobs use that repository's flake and toolchain pins. Fish's application
code stays in `/home/will/src/fish.foo`, consumed through the `fish-app-src`
source input. The Nix configuration selects only its three service scripts.
This preserves the existing uncommitted application change and keeps application
code outside this repository. Until that application has a remote repository,
this input depends on its local path and the flake is not fully portable. Run
`nix flake update fish-app-src` after intentionally updating the application.
Other reusable services come from pinned module repositories.

## Host operations

Host-specific commands live in `hosts/<name>/justfile`, loaded as native just
modules. The root justfile only declares their namespaces:

```sh
just nero                         # List Nero commands
just nero logs signet
just nero guix-queue
just nero guix-submit COMMIT
just beelink status
just beelink bench-submit COMMIT
just guix-arm-builder status
just fish-foo ssh
just --dry-run beelink services restart
```

These recipes manage the configured hosts over SSH. Nero's former `arm-status`
and `arm-poweroff` are now `just guix-arm-builder status` and
`just guix-arm-builder poweroff`. Use `just switch guix-arm-builder` to update
that host. Deployment recipes remain at the top level.

Application helpers stay with their source: Nero's Python-backed `review-pr`
remains in `/home/will/src/nero`, and benchmark dashboard previews remain in
`/home/will/src/core/ci`. The old dashboard sync/update recipes target
`/etc/nixos/jobs`; they do not update this deployment's pinned CI application.
Change the application source and update `bitcoin-core-ci` instead. Pin updates
use `nix flake update INPUT`, for example `nix flake update nero-will-nix`.

## First installation

`deploy` uses nixos-anywhere and erases the disks declared by the host's Disko
configuration. It targets the same hardware described in the host directory.
Check disk identifiers and the installation SSH target in `justfile` before
using it. Rescue SSH is usually port 22, including Nero.

```sh
just --yes --dry-run deploy-nero
just deploy nero
```

The per-host recipe uses just's built-in confirmation before installation.
There is no `deploy-all` recipe. Beelink has no Disko layout, so its first
installation is not yet implemented; `switch beelink` works with the existing
installation.

Before installing, prepare `$HOME/.config/deployments/HOST/` as a directory
tree matching the destination filesystem. nixos-anywhere copies it with
`--extra-files`. Place the host's existing private identity at:

| Host | Path inside that directory |
| --- | --- |
| nero | `var/lib/sops-nix/key.txt` |
| fish-foo | `root/.config/sops/age/keys.txt` |
| kestrel | `etc/ssh/ssh_host_ed25519_key` |
| guix-publish-2 | `var/lib/sops-nix/key.txt` |

For example, prepare Nero's files once using its existing age identity:

```sh
umask 077
install -Dm600 /path/to/existing/nero.txt \
  "$HOME/.config/deployments/nero/var/lib/sops-nix/key.txt"
```

Use identities that match the recipients in `.sops.yaml`. CDash needs its
existing SSH host private key, not your login key. Include its public companion
at `etc/ssh/ssh_host_ed25519_key.pub`. The ARM builder needs no extra files.
These directories persist for reuse; the recipes do not generate or check keys.

Keep private keys outside this Git repository. Existing Nero and Guix private
identities remain in their old repositories' ignored `keys/` directories until
you place them in your private key storage. A switch uses keys already installed
on each host and needs no local SOPS identity.

## Secrets

Edit from the repository root, for example:

```sh
sops secrets/beelink/secrets.yaml
sops secrets/nero/secrets.yaml
```

Ciphertext was copied unchanged. The SOPS recipient sets and runtime key paths
remain as before. Nero retains a recipient shared with the excluded old DNS
seed host. Its DNSSEC and Guix files remain separate encrypted files. The Guix
`.asc` files are public detached signatures and are excluded from SOPS rules.

After intentionally changing a recipient rule, run `sops updatekeys` on the
specific affected encrypted file. Moving these files did not require a rekey.
Never add private age or SSH identities to the flake: tracked sources enter the
Nix store. The shared flake contains all hosts' ciphertext, while recipient
rules continue to control which identities can decrypt each file.

## Updates and verification

```sh
nix flake update nixpkgs
just check
just build nero
just switch nero
```

Update a service input separately, for example `nix flake update nero-will-nix`.
The group prefixes preserve old service revisions; they do not imply different
server nixpkgs versions. Review `flake.lock` before switching. Build and inspect
one host at a time for the first unstable rollout.

Use `just --dry-run switch-all` to inspect routing, `just check` for evaluation,
and `just build HOST` to verify builds without activation.
[Migration notes](docs/migration.md) record the source inventory and comparison
checks. `implementation.md` records local design decisions and is not committed.

## Kestrel CDash host

`kestrel` replaces the former `cdash-server` host name. It serves
`https://cdash.fish.foo` on the existing machine at `46.225.46.115`.
Use `just build kestrel` to build without activation. Future updates use
`just switch kestrel` or `just switch-remote kestrel`.

The pinned `cdash-src` input supplies the CDash 5.5.2 package and service module.
Host settings live in `hosts/kestrel/`, including the 192 MiB upload limit,
256 MiB request limit and 2000-second submission timeouts from the source
checkout. Keep the existing database, `/var/lib/cdash`, and application key
when switching. The project's 5 GiB attachment quota is stored in its database.
Back up that database before upgrading; a NixOS rollback cannot undo migrations.

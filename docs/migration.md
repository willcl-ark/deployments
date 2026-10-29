# Migration plan

1. Import the five named projects into one deployment flake, retaining their
   existing pins and current tracked configuration contents. Keep source
   repositories untouched. Verify each host against its previous configuration.
2. Extract common server defaults. Keep networking, boot, storage, service data,
   SSH access policies, SOPS identities and system.stateVersion host specific.
3. Move all server configurations to one pinned nixpkgs unstable revision.
   Use a shared SOPS-Nix revision compatible with unstable; keep other service
   module pins and CI job toolchains independently pinned.
4. Validate every system derivation and test command routing without connecting
   to the hosts. Build configurations before the first live switch.
5. Switch hosts individually, inspect services, then use fleet switching for
   routine changes. A live switch is a separate operation from this migration.

## Inventory

| Configuration | Source | Service |
| --- | --- | --- |
| nero | /home/will/src/nero | Forgejo, Ralph, Guix, DNS seed, caches, monitoring |
| beelink | /home/will/src/core/ci | Bitcoin Core CI and benchmarks |
| fish-foo | /home/will/src/fish.foo | Landing page, DNS monitoring, Nero watchdog |
| cdash-server | /home/will/src/core/bitcoin/cdash-server | CDash |
| guix-publish-2 | /home/will/src/guix-publish-2 | Guix publishing and Nero replication |
| guix-arm-builder | /home/will/src/nero | On-demand native ARM Guix builds |

The separate old `dnsseed` host is excluded at Will's request. Nero's active
DNS seed service remains. The ARM builder is normally powered off by Nero.

Other flakes with NixOS configurations were found under src, including
bitcoin-dev-tools/{nix-guix-builder,nix-seed-node,nix-dev-server,nix-github-runner,
usdt-dash,ipc-dash}, docker-registry-cache and
core/{nixos-depends-sources,nix-firecracker-ci,nix-ci,nix-onion-proxy,nix-guix-ci,
nix-benchmark,nix-ci-github}. These may be templates or retired deployments;
they have not been imported or treated as active servers.

## Preservation checks

Before changing pins, the imported Nero, ARM builder, fish-foo, CDash and Guix
publish modules produced exactly their original system derivation paths.
Beelink's runner jobs, runner service configuration, package list and tmpfiles
matched. Its system derivation changes because the application now comes from
a pinned repository input and its encrypted file moves.

The source fish.foo configuration.nix and server.py had existing modifications;
the initial comparison used those current contents. The final configuration
consumes application scripts from a local source input, since this application
has no remote repository. No Python application or deployment scripts live here. Existing local build artifacts,
.direnv state, plaintext keys and implementation notes were excluded.

Ciphertext files and their recipients are preserved. Nero still includes the
old DNS seed recipient. Removing that recipient requires an explicit later
rekey, once the old host's status is confirmed. Public detached signatures are
kept beside their encrypted Guix public keys.

The old repositories remain on disk for application development and reference.
Use this directory for host changes and deployment from now on. The old deploy
recipes have not been edited, and there is no compatibility wrapper back to
those configurations.

## Unstable adjustments

All six hosts use nixos-unstable revision
`31ecbaca1bdefa45dffc409f0250bd8039ea0010`. Older SOPS-Nix inputs required a
removed Go builder, so the hosts now share Nero's newer SOPS-Nix revision.
Nero's journald retention values use the current structured option.

A one-line source patch updates the pinned Bitcoin DNS seed module to the new
I2P option name. The patch is applied before importing that module, requiring a
small build during evaluation. Remove it once the reusable module supports the
new option and its pin is deliberately updated.

Will chose current I2P defaults, including a transient SOCKS identity. The
web console and HTTP proxy now listen on localhost; transport publication and
exploratory tunnel settings follow packaged defaults. Nero retains its
10.200.1.0 SOCKS address. The new startup-based build check cannot bind that
runtime-only address, so the host disables it. A validation-only loopback
override successfully passed the same check.

Nero and fish.foo share one Caddy Cloudflare package definition. Its fixed-output
hash was updated after building against the common unstable Caddy version.

The deployment interface uses just recipes and standard command-line tools.
Application test suites belong in their application repositories.

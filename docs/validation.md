# Validation on 2026-10-29

All six complete system closures built locally without activation:

- nero
- beelink
- fish-foo
- cdash-server
- guix-publish-2
- guix-arm-builder

Every host uses nixpkgs revision
`31ecbaca1bdefa45dffc409f0250bd8039ea0010`. Existing stateVersion values remain
25.11, except CDash and ARM which remain 26.05.

`nix flake check --no-build --all-systems --no-update-lock-file` passed.
The Bash recipes passed ShellCheck. Command previews checked fleet membership,
Nero's port, CDash's sudo access, ARM's identity and first-install arguments.
Beelink and `all` correctly reject first installation.

All 17 encrypted files and both detached signatures match their source bytes.
Each encrypted file matches one central SOPS rule with the original recipients.
No private machine identities were imported or secrets decrypted.

Nero's I2P configuration check passed with a validation-only loopback binding.
The host disables that startup-based build check because its real veth address
exists only at runtime. Production assertions and NixOS option checking remain
enabled.

CDash's pinned shared module emits a PHP-FPM `phpOptions` deprecation warning.
Its system builds successfully; migrating that module's option format can be a
separate change.

No live switch, installation, source-repository modification, or GitHub write
was performed. Service health after activation remains to be checked during
the first host-by-host rollout. Fish's application source remains a local input
until its repository is published.

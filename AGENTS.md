# Deployment repository

Keep this repository almost entirely Nix. Use Nix modules and simple just
recipes for deployment. Do not add Python deployment tooling or a separate
test harness. Validate with Nix evaluation/builds and command previews.
Prefer explicit per-host commands. Use just's built-in dry runs, confirmations
and recipe dependencies instead of custom dispatch or command-building logic.

Application source belongs in its application repository and should be consumed
as a flake input. Keep host configuration here. Ask before generalizing differing
host settings; use ordinary NixOS module overrides for intentional exceptions.

`deploy` means destructive first installation. `switch` updates an existing
host. Do not run either against live machines unless the user requests it.

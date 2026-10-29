set positional-arguments

default:
    @just --list

hosts:
    nix eval --json --no-update-lock-file .#nixosConfigurations --apply builtins.attrNames

check:
    nix flake check --no-build --all-systems --no-update-lock-file

build host:
    nix build --no-update-lock-file --no-link ".#nixosConfigurations.$1.config.system.build.toplevel"

switch host:
    @just switch-"$1"

switch-all: switch-nero switch-beelink switch-fish-foo switch-cdash-server switch-guix-publish-2

switch-nero:
    NIX_SSHOPTS='-p 2222' nixos-rebuild switch --flake .#nero --build-host root@nero --target-host root@nero --no-reexec --no-update-lock-file

switch-beelink:
    nixos-rebuild switch --flake .#beelink --build-host root@beelink --target-host root@beelink --no-reexec --no-update-lock-file

switch-fish-foo:
    nixos-rebuild switch --flake .#fish-foo --build-host root@fish.foo --target-host root@fish.foo --no-reexec --no-update-lock-file

switch-cdash-server:
    NIX_SSHOPTS="-i $HOME/.ssh/hetzner-temp" nixos-rebuild switch --flake .#cdash-server --build-host will@46.225.46.115 --target-host will@46.225.46.115 --sudo --no-reexec --no-update-lock-file

switch-guix-publish-2:
    nixos-rebuild switch --flake .#guix-publish-2 --build-host root@guix-publish-2 --target-host root@guix-publish-2 --no-reexec --no-update-lock-file

# This machine is normally powered off, so it is excluded from switch-all.
switch-guix-arm-builder:
    NIX_SSHOPTS="-i $HOME/.ssh/guix-builder-aarch64.pem" nixos-rebuild switch --flake .#guix-arm-builder --build-host root@arm-guix-builder --target-host root@arm-guix-builder --no-reexec --no-update-lock-file

# First installation erases the host's disks. Prepare extra files as in README.md.
deploy host:
    @just deploy-"$1"

[confirm('Erase the disks on Nero and install NixOS?')]
deploy-nero:
    nix run --no-update-lock-file .#nixos-anywhere -- --flake .#nero --target-host root@nero --ssh-port 22 --extra-files "$HOME/.config/deployments/nero"

[confirm('Erase the disks on fish.foo and install NixOS?')]
deploy-fish-foo:
    nix run --no-update-lock-file .#nixos-anywhere -- --flake .#fish-foo --target-host root@fish.foo --ssh-port 22 --extra-files "$HOME/.config/deployments/fish-foo"

[confirm('Erase the disks on CDash and install NixOS?')]
deploy-cdash-server:
    nix run --no-update-lock-file .#nixos-anywhere -- --flake .#cdash-server --target-host root@46.225.46.115 --ssh-port 22 -i "$HOME/.ssh/hetzner-temp" --kexec-extra-flags --kexec-syscall --extra-files "$HOME/.config/deployments/cdash-server"

[confirm('Erase the disks on guix-publish-2 and install NixOS?')]
deploy-guix-publish-2:
    nix run --no-update-lock-file .#nixos-anywhere -- --flake .#guix-publish-2 --target-host root@guix-publish-2 --ssh-port 22 --extra-files "$HOME/.config/deployments/guix-publish-2"

[confirm('Erase the disks on the ARM Guix builder and install NixOS?')]
deploy-guix-arm-builder:
    nix run --no-update-lock-file .#nixos-anywhere -- --flake .#guix-arm-builder --target-host root@arm-guix-builder --ssh-port 22 -i "$HOME/.ssh/guix-builder-aarch64.pem"

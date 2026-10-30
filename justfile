set positional-arguments

# Nero operations.
mod nero 'hosts/nero/justfile'
# CI operations.
mod beelink 'hosts/beelink/justfile'
# ARM builder operations.
mod guix-arm-builder 'hosts/guix-arm-builder/justfile'
# fish.foo operations.
mod fish-foo 'hosts/fish-foo/justfile'

# List commands.
[private]
default:
    @just --list

# List configured hosts.
hosts:
    nix eval --json --no-update-lock-file .#nixosConfigurations --apply builtins.attrNames

# Evaluate all host configurations.
check:
    nix flake check --no-build --all-systems --no-update-lock-file

# Build a host locally without activation.
build host:
    nix build --no-update-lock-file --no-link ".#nixosConfigurations.$1.config.system.build.toplevel"

# Build and activate remotely; accepts all.
switch host:
    @just switch-"$1"

# Update the five always-on hosts.
[private]
switch-all: switch-nero switch-beelink switch-fish-foo switch-cdash-server switch-guix-publish-2

# Update Nero.
[private]
switch-nero:
    NIX_SSHOPTS='-p 2222' nixos-rebuild switch --flake .#nero --build-host root@nero --target-host root@nero --no-reexec --no-update-lock-file

# Update Beelink.
[private]
switch-beelink:
    nixos-rebuild switch --flake .#beelink --build-host root@beelink --target-host root@beelink --no-reexec --no-update-lock-file

# Update fish.foo.
[private]
switch-fish-foo:
    nixos-rebuild switch --flake .#fish-foo --build-host root@fish.foo --target-host root@fish.foo --no-reexec --no-update-lock-file

# Update CDash through sudo.
[private]
switch-cdash-server:
    NIX_SSHOPTS="-i $HOME/.ssh/hetzner-temp" nixos-rebuild switch --flake .#cdash-server --build-host will@46.225.46.115 --target-host will@46.225.46.115 --sudo --no-reexec --no-update-lock-file

# Update the Guix publisher.
[private]
switch-guix-publish-2:
    nixos-rebuild switch --flake .#guix-publish-2 --build-host root@guix-publish-2 --target-host root@guix-publish-2 --no-reexec --no-update-lock-file

# Update ARM when running; excluded from all.
[private]
switch-guix-arm-builder:
    NIX_SSHOPTS="-i $HOME/.ssh/guix-builder-aarch64.pem" nixos-rebuild switch --flake .#guix-arm-builder --build-host root@arm-guix-builder --target-host root@arm-guix-builder --no-reexec --no-update-lock-file

# Rsync, then evaluate and switch on the host.
switch-remote host:
    @just switch-remote-"$1"

# Update ready hosts; excludes fish.foo and ARM.
[private]
switch-remote-all: switch-remote-nero switch-remote-beelink switch-remote-cdash-server switch-remote-guix-publish-2

# Sync and switch Nero remotely.
[private]
switch-remote-nero:
    rsync -az --delete --mkpath --exclude='.git' --filter=':- .gitignore' -e 'ssh -p 2222' ./ root@nero:/var/lib/nixos-deployments/
    ssh -p 2222 root@nero 'nixos-rebuild switch --flake path:/var/lib/nixos-deployments#nero --no-update-lock-file'

# Sync and switch Beelink remotely.
[private]
switch-remote-beelink:
    rsync -az --delete --mkpath --exclude='.git' --filter=':- .gitignore' ./ root@beelink:/var/lib/nixos-deployments/
    ssh root@beelink 'nixos-rebuild switch --flake path:/var/lib/nixos-deployments#beelink --no-update-lock-file'

# Sync and switch CDash through sudo.
[private]
switch-remote-cdash-server:
    rsync -az --delete --mkpath --exclude='.git' --filter=':- .gitignore' -e "ssh -i $HOME/.ssh/hetzner-temp" --rsync-path='sudo -n rsync' ./ will@46.225.46.115:/var/lib/nixos-deployments/
    ssh -i "$HOME/.ssh/hetzner-temp" will@46.225.46.115 'sudo -n nixos-rebuild switch --flake path:/var/lib/nixos-deployments#cdash-server --no-update-lock-file'

# Sync and switch the Guix publisher remotely.
[private]
switch-remote-guix-publish-2:
    rsync -az --delete --mkpath --exclude='.git' --filter=':- .gitignore' ./ root@guix-publish-2:/var/lib/nixos-deployments/
    ssh root@guix-publish-2 'nixos-rebuild switch --flake path:/var/lib/nixos-deployments#guix-publish-2 --no-update-lock-file'

# Sync and switch ARM when running.
[private]
switch-remote-guix-arm-builder:
    rsync -az --delete --mkpath --exclude='.git' --filter=':- .gitignore' -e "ssh -i $HOME/.ssh/guix-builder-aarch64.pem" ./ root@arm-guix-builder:/var/lib/nixos-deployments/
    ssh -i "$HOME/.ssh/guix-builder-aarch64.pem" root@arm-guix-builder 'nixos-rebuild switch --flake path:/var/lib/nixos-deployments#guix-arm-builder --no-update-lock-file'

# Install a host, erasing its disks; see README.
deploy host:
    @just deploy-"$1"

# Fresh-install Nero.
[confirm('Erase the disks on Nero and install NixOS?')]
[private]
deploy-nero:
    nix run --no-update-lock-file .#nixos-anywhere -- --flake .#nero --target-host root@nero --ssh-port 22 --extra-files "$HOME/.config/deployments/nero"

# Fresh-install fish.foo.
[confirm('Erase the disks on fish.foo and install NixOS?')]
[private]
deploy-fish-foo:
    nix run --no-update-lock-file .#nixos-anywhere -- --flake .#fish-foo --target-host root@fish.foo --ssh-port 22 --extra-files "$HOME/.config/deployments/fish-foo"

# Fresh-install CDash.
[confirm('Erase the disks on CDash and install NixOS?')]
[private]
deploy-cdash-server:
    nix run --no-update-lock-file .#nixos-anywhere -- --flake .#cdash-server --target-host root@46.225.46.115 --ssh-port 22 -i "$HOME/.ssh/hetzner-temp" --kexec-extra-flags --kexec-syscall --extra-files "$HOME/.config/deployments/cdash-server"

# Fresh-install the Guix publisher.
[confirm('Erase the disks on guix-publish-2 and install NixOS?')]
[private]
deploy-guix-publish-2:
    nix run --no-update-lock-file .#nixos-anywhere -- --flake .#guix-publish-2 --target-host root@guix-publish-2 --ssh-port 22 --extra-files "$HOME/.config/deployments/guix-publish-2"

# Fresh-install the ARM builder.
[confirm('Erase the disks on the ARM Guix builder and install NixOS?')]
[private]
deploy-guix-arm-builder:
    nix run --no-update-lock-file .#nixos-anywhere -- --flake .#guix-arm-builder --target-host root@arm-guix-builder --ssh-port 22 -i "$HOME/.ssh/guix-builder-aarch64.pem"

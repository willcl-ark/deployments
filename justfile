set positional-arguments

default:
    @just --list

hosts:
    #!/usr/bin/env bash
    set -euo pipefail
    nix eval --json --no-update-lock-file --no-write-lock-file .#deployments | jq -r 'to_entries[] | "\(.key): \(.value.target) port \(.value.port) (\(.value.system), switch all=\(.value.all))"'

plan action host:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$1" in check|build|switch|deploy) ;; *) echo "Unknown action: $1" >&2; exit 1;; esac
    DEPLOY_DRY_RUN=1 just "$1" "$2"

check host:
    @just _rebuild check "$1"

build host:
    @just _rebuild build "$1"

switch host:
    @just _rebuild switch "$1"

[private]
_rebuild action host:
    #!/usr/bin/env bash
    set -euo pipefail
    action=$1
    requested=$2
    registry=$(nix eval --json --no-update-lock-file --no-write-lock-file .#deployments)
    if [[ $requested == all ]]; then
        mapfile -t names < <(jq -r --arg action "$action" 'to_entries[] | select($action != "switch" or .value.all) | .key' <<< "$registry")
    else
        jq -e --arg name "$requested" 'has($name)' <<< "$registry" >/dev/null || { echo "Unknown host: $requested" >&2; exit 1; }
        names=("$requested")
    fi
    for name in "${names[@]}"; do
        host=$(jq -c --arg name "$name" '.[$name]' <<< "$registry")
        case "$action" in
            check) command=(nix eval --raw --no-update-lock-file --no-write-lock-file ".#nixosConfigurations.$name.config.system.build.toplevel.drvPath");;
            build) command=(nix build --no-update-lock-file --no-link ".#nixosConfigurations.$name.config.system.build.toplevel");;
            switch)
                target=$(jq -r '.target' <<< "$host")
                port=$(jq -r '.port' <<< "$host")
                identity=$(jq -r '.identity // empty' <<< "$host")
                ssh_options=(-p "$port")
                [[ -z $identity ]] || ssh_options+=(-i "${identity/#\~/$HOME}")
                printf -v options '%q ' "${ssh_options[@]}"
                command=(env "NIX_SSHOPTS=${NIX_SSHOPTS:+$NIX_SSHOPTS }${options% }" nixos-rebuild switch --flake ".#$name" --build-host "$target" --target-host "$target" --no-reexec --no-update-lock-file)
                [[ $(jq -r '.sudo // false' <<< "$host") == false ]] || command+=(--sudo)
                ;;
            *) echo "Unknown action: $action" >&2; exit 1;;
        esac
        printf '%s: %s\n' "$name" "$action"
        printf '%q ' "${command[@]}"; printf '\n'
        if [[ ${DEPLOY_DRY_RUN:-0} != 1 ]]; then
            "${command[@]}"
            printf '\n'
        fi
    done

deploy host *args:
    #!/usr/bin/env bash
    set -euo pipefail
    name=$1
    shift
    confirmed=false
    if [[ $# == 1 && $1 == --yes ]]; then confirmed=true; shift; fi
    [[ $# == 0 ]] || { echo 'Usage: just deploy HOST [--yes]' >&2; exit 1; }
    [[ $name != all ]] || { echo 'First installation requires one host; deploy all is disabled.' >&2; exit 1; }
    registry=$(nix eval --json --no-update-lock-file --no-write-lock-file .#deployments)
    jq -e --arg name "$name" 'has($name)' <<< "$registry" >/dev/null || { echo "Unknown host: $name" >&2; exit 1; }
    host=$(jq -c --arg name "$name" '.[$name]' <<< "$registry")
    jq -e '.install != null' <<< "$host" >/dev/null || { echo "$name has no declarative disk layout; use switch for its existing installation." >&2; exit 1; }
    target=$(jq -r '.install.target' <<< "$host")
    port=$(jq -r '.install.port' <<< "$host")
    identity=$(jq -r '.identity // empty' <<< "$host")
    command=(nix run --no-update-lock-file .#nixos-anywhere -- --flake ".#$name" --target-host "$target" --ssh-port "$port")
    [[ -z $identity ]] || command+=(-i "${identity/#\~/$HOME}")
    mapfile -t extra_args < <(jq -r '.install.extraArgs // [] | .[]' <<< "$host")
    command+=("${extra_args[@]}")
    key_type=$(jq -r '.install.keyType // empty' <<< "$host")
    if [[ ${DEPLOY_DRY_RUN:-0} != 1 && $confirmed == false ]]; then
        read -r -p "First installation will erase disks on $target. Type $name to continue: " answer
        [[ $answer == "$name" ]] || { echo 'Installation cancelled.' >&2; exit 1; }
    fi
    if [[ -n $key_type ]]; then
        if [[ ${DEPLOY_DRY_RUN:-0} == 1 ]]; then
            command+=(--extra-files '<staged-SOPS-key>')
        else
            : "${SOPS_KEY_FILE:?Set SOPS_KEY_FILE to the existing private SOPS identity outside the repository}"
            key=$(realpath -e -- "$SOPS_KEY_FILE")
            [[ -f $key && $key != "$(pwd -P)/"* ]] || { echo 'SOPS_KEY_FILE must be a file outside the repository.' >&2; exit 1; }
            key_path=$(jq -r '.install.keyPath' <<< "$host")
            [[ $key_path == /* && $key_path != */../* && $key_path != */.. ]] || { echo 'Invalid install.keyPath.' >&2; exit 1; }
            umask 077
            staging=$(mktemp -d)
            trap 'rm -rf -- "$staging"' EXIT
            staged="$staging$key_path"
            mkdir -p -- "$(dirname -- "$staged")"
            install -m 600 -- "$key" "$staged"
            case "$key_type" in
                age) recipient=$(age-keygen -y "$staged");;
                ssh)
                    ssh-keygen -y -f "$staged" > "$staged.pub"
                    recipient=$(ssh-to-age < "$staged.pub")
                    ;;
                *) echo "Unsupported SOPS identity type: $key_type" >&2; exit 1;;
            esac
            [[ $recipient == "$(jq -r '.install.recipient' <<< "$host")" ]] || { echo "SOPS_KEY_FILE does not match $name's configured recipient." >&2; exit 1; }
            command+=(--extra-files "$staging")
        fi
    fi
    printf '%s: deploy\n' "$name"
    printf '%q ' "${command[@]}"; printf '\n'
    if [[ ${DEPLOY_DRY_RUN:-0} != 1 ]]; then "${command[@]}"; fi

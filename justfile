set positional-arguments

default:
    @just --list

hosts:
    python3 scripts/deploy.py list

plan action host:
    python3 scripts/deploy.py plan "$1" "$2"

check host:
    python3 scripts/deploy.py check "$1"

build host:
    python3 scripts/deploy.py build "$1"

switch host:
    python3 scripts/deploy.py switch "$1"

deploy host *args:
    python3 scripts/deploy.py deploy "$@"

#!/usr/bin/env python3
"""Run deployment commands from the root host registry."""

import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
ACTIONS = ("check", "build", "switch", "deploy")


def run(command, **kwargs):
    return subprocess.run(command, cwd=ROOT, check=True, **kwargs)


def load_hosts():
    result = run(
        ["nix", "eval", "--json", "--no-update-lock-file", "--no-write-lock-file", ".#deployments"],
        capture_output=True, text=True,
    )
    return json.loads(result.stdout)


def select_hosts(hosts, name, action):
    if name == "all":
        if action == "deploy":
            raise ValueError("deploy requires one host; first installation cannot target all")
        return [
            (name, host) for name, host in hosts.items()
            if action != "switch" or host.get("all", False)
        ]
    if name not in hosts:
        raise ValueError(f"unknown host {name!r}; choose from {', '.join(hosts)}")
    if action == "deploy" and hosts[name].get("install") is None:
        raise ValueError(f"{name} has no declarative disk layout; use switch for its existing installation")
    return [(name, hosts[name])]


def command_for(action, name, host, extra_files=None):
    env = os.environ.copy()
    toplevel = f".#nixosConfigurations.{name}.config.system.build.toplevel"
    if action == "check":
        return ["nix", "eval", "--raw", "--no-update-lock-file", "--no-write-lock-file", toplevel + ".drvPath"], env
    if action == "build":
        return ["nix", "build", "--no-update-lock-file", "--no-link", toplevel], env
    identity = os.path.expanduser(host["identity"]) if host.get("identity") else None
    if action == "switch":
        ssh_options = ["-p", str(host["port"])]
        if identity:
            ssh_options.extend(["-i", identity])
        env["NIX_SSHOPTS"] = " ".join(filter(None, [
            env.get("NIX_SSHOPTS", ""), shlex.join(ssh_options),
        ]))
        command = [
            "nixos-rebuild", "switch", "--flake", f".#{name}",
            "--build-host", host["target"], "--target-host", host["target"],
            "--no-reexec", "--no-update-lock-file",
        ]
        if host.get("sudo", False):
            command.append("--sudo")
        return command, env
    install = host["install"]
    command = [
        "nix", "run", "--no-update-lock-file", ".#nixos-anywhere", "--", "--flake", f".#{name}",
        "--target-host", install["target"], "--ssh-port", str(install["port"]),
    ]
    if identity:
        command.extend(["-i", identity])
    if extra_files:
        command.extend(["--extra-files", str(extra_files)])
    command.extend(install.get("extraArgs", []))
    return command, env


@contextmanager
def staged_key(install):
    if not install.get("keyType"):
        yield None
        return
    source_name = os.environ.get("SOPS_KEY_FILE")
    if not source_name:
        raise ValueError("set SOPS_KEY_FILE to this host's existing private SOPS identity outside the repository")
    source = Path(source_name).expanduser().resolve()
    if source.is_relative_to(ROOT) or not source.is_file():
        raise ValueError("SOPS_KEY_FILE must be a file outside the repository")
    key_path = Path(install["keyPath"])
    if not key_path.is_absolute() or ".." in key_path.parts:
        raise ValueError("install.keyPath must be an absolute path without '..'")
    with tempfile.TemporaryDirectory(prefix="deploy-sops-") as directory:
        staged = Path(directory) / key_path.relative_to("/")
        staged.parent.mkdir(parents=True, exist_ok=True)
        with staged.open("xb") as output:
            staged.chmod(0o600)
            with source.open("rb") as private_key:
                shutil.copyfileobj(private_key, output)
        if install["keyType"] == "age":
            recipient = run(["age-keygen", "-y", str(staged)], capture_output=True, text=True).stdout.strip()
        elif install["keyType"] == "ssh":
            public_key = run(["ssh-keygen", "-y", "-f", str(staged)], capture_output=True, text=True).stdout
            recipient = run(["ssh-to-age"], input=public_key, capture_output=True, text=True).stdout.strip()
            staged.with_suffix(staged.suffix + ".pub").write_text(public_key)
        else:
            raise ValueError(f"unsupported SOPS identity type: {install['keyType']}")
        if recipient != install["recipient"]:
            raise ValueError("SOPS_KEY_FILE does not match this host's configured recipient")
        yield directory


def show_command(name, action, command, env):
    print(f"{name}: {action}", flush=True)
    prefix = ""
    if action == "switch":
        prefix = "NIX_SSHOPTS=" + shlex.quote(env["NIX_SSHOPTS"]) + " "
    print(prefix + shlex.join(command), flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="list registered hosts")
    plan = commands.add_parser("plan", help="print commands without building or connecting")
    plan.add_argument("action", choices=ACTIONS)
    plan.add_argument("host")
    for action in ACTIONS:
        command = commands.add_parser(action)
        command.add_argument("host")
        if action == "deploy":
            command.add_argument("--yes", action="store_true", help="confirm destructive first installation")
    args = parser.parse_args(argv)
    try:
        hosts = load_hosts()
        if args.command == "list":
            for name, host in hosts.items():
                print(f"{name}: {host['target']} port {host['port']} ({host['system']}, all={str(host.get('all', False)).lower()})")
            return 0
        action = args.action if args.command == "plan" else args.command
        selected = select_hosts(hosts, args.host, action)
        for name, host in selected:
            if action == "deploy" and args.command != "plan":
                if not args.yes:
                    answer = input(f"First installation will erase disks on {host['install']['target']}. Type {name} to continue: ")
                    if answer != name:
                        raise ValueError("installation cancelled")
                with staged_key(host["install"]) as directory:
                    command, env = command_for(action, name, host, directory)
                    show_command(name, action, command, env)
                    run(command, env=env)
            else:
                extra_files = "<staged-SOPS-key>" if action == "deploy" and host["install"].get("keyType") else None
                command, env = command_for(action, name, host, extra_files)
                show_command(name, action, command, env)
                if args.command != "plan":
                    run(command, env=env)
        return 0
    except (ValueError, OSError, EOFError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(f"error: command failed with exit code {error.returncode}: {shlex.join(error.cmd)}", file=sys.stderr)
        return error.returncode or 1


if __name__ == "__main__":
    sys.exit(main())

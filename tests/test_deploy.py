"""Exercise the deployment CLI without running Nix or contacting hosts."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("deploy", Path(__file__).parents[1] / "scripts" / "deploy.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)

HOSTS = {
    "nero": {
        "target": "root@nero", "port": 2222, "system": "x86_64-linux", "all": True,
        "install": {
            "target": "root@nero", "port": 22, "keyType": "age",
            "keyPath": "/var/lib/sops-nix/key.txt", "recipient": "age1expected",
        },
    },
    "cdash-server": {
        "target": "will@46.225.46.115", "port": 22, "sudo": True,
        "system": "x86_64-linux", "all": True,
        "install": {
            "target": "root@46.225.46.115", "port": 22, "keyType": "ssh",
            "keyPath": "/etc/ssh/ssh_host_ed25519_key", "recipient": "age1expected",
            "extraArgs": ["--kexec-extra-flags", "--kexec-syscall"],
        },
    },
    "beelink": {
        "target": "root@beelink", "port": 22, "system": "x86_64-linux",
        "all": True, "install": None,
    },
    "guix-arm-builder": {
        "target": "root@arm-guix-builder", "port": 22, "all": False,
        "system": "aarch64-linux", "identity": "~/.ssh/guix-builder-aarch64.pem",
        "install": {"target": "root@arm-guix-builder", "port": 22},
    },
}


class DeployTests(unittest.TestCase):
    def setUp(self):
        self.output = io.StringIO()
        self.enterContext(contextlib.redirect_stdout(self.output))
        self.enterContext(contextlib.redirect_stderr(self.output))
        self.process = self.enterContext(patch.object(deploy.subprocess, "run"))
        self.process.side_effect = self.respond

    def respond(self, command, **kwargs):
        if command[:2] == ["nix", "eval"] and command[-1] == ".#deployments":
            return subprocess.CompletedProcess(command, 0, json.dumps(HOSTS))
        return subprocess.CompletedProcess(command, 0, "")

    def test_switch_targets_and_sudo(self):
        with patch.dict(os.environ, {"NIX_SSHOPTS": "-o ConnectTimeout=10"}):
            self.assertEqual(deploy.main(["switch", "all"]), 0)
        calls = self.process.call_args_list[1:]
        self.assertEqual(len(calls), 3)
        for call, target in zip(calls, ["root@nero", "will@46.225.46.115", "root@beelink"]):
            command = call.args[0]
            self.assertEqual(command[command.index("--build-host") + 1], target)
            self.assertEqual(command[command.index("--target-host") + 1], target)
            self.assertIn("--no-reexec", command)
            self.assertIn("--no-update-lock-file", command)
            self.assertEqual(call.kwargs["cwd"], deploy.ROOT)
        self.assertEqual(calls[0].kwargs["env"]["NIX_SSHOPTS"], "-o ConnectTimeout=10 -p 2222")
        self.assertNotIn("--sudo", calls[0].args[0])
        self.assertIn("--sudo", calls[1].args[0])

    def test_optional_identity_is_expanded(self):
        with patch.dict(os.environ, {"HOME": "/tmp/deploy-test-home"}, clear=True):
            self.assertEqual(deploy.main(["switch", "guix-arm-builder"]), 0)
        self.assertEqual(self.process.call_args.kwargs["env"]["NIX_SSHOPTS"], "-p 22 -i /tmp/deploy-test-home/.ssh/guix-builder-aarch64.pem")

    def test_plan_only_evaluates_registry(self):
        for action in ("switch", "check", "build", "deploy"):
            with self.subTest(action=action):
                self.process.reset_mock()
                self.assertEqual(deploy.main(["plan", action, "nero"]), 0)
                self.process.assert_called_once()
                self.assertIn("--no-write-lock-file", self.process.call_args.args[0])
                self.assertIn("--no-update-lock-file", self.process.call_args.args[0])
        self.assertIn("<staged-SOPS-key>", self.output.getvalue())
        self.assertIn("--ssh-port 22", self.output.getvalue())

    def test_build_and_check_select_correct_attributes(self):
        self.assertEqual(deploy.main(["build", "nero"]), 0)
        self.assertEqual(self.process.call_args.args[0], ["nix", "build", "--no-update-lock-file", "--no-link", ".#nixosConfigurations.nero.config.system.build.toplevel"])
        self.assertEqual(deploy.main(["check", "all"]), 0)
        checks = self.process.call_args_list[-4:]
        self.assertEqual(len(checks), 4)
        for call in checks:
            self.assertEqual(call.args[0][:3], ["nix", "eval", "--raw"])
            self.assertTrue(call.args[0][-1].endswith(".drvPath"))
            self.assertIn("--no-update-lock-file", call.args[0])
        self.assertIn("guix-arm-builder", checks[-1].args[0][-1])

    def test_build_all_includes_offline_arm_host(self):
        self.assertEqual(deploy.main(["build", "all"]), 0)
        builds = self.process.call_args_list[1:]
        self.assertEqual(len(builds), len(HOSTS))
        self.assertEqual(builds[-1].args[0][-1], ".#nixosConfigurations.guix-arm-builder.config.system.build.toplevel")

    def test_all_stops_after_first_failure(self):
        def fail_switch(command, **kwargs):
            if command[0] == "nixos-rebuild":
                raise subprocess.CalledProcessError(42, command)
            return self.respond(command, **kwargs)
        self.process.side_effect = fail_switch
        self.assertEqual(deploy.main(["switch", "all"]), 42)
        self.assertEqual(self.process.call_count, 2)

    def test_reject_unknown_host_and_unsupported_installs(self):
        for arguments in (["switch", "missing"], ["deploy", "all", "--yes"], ["deploy", "beelink", "--yes"]):
            with self.subTest(arguments=arguments):
                self.process.reset_mock()
                self.assertEqual(deploy.main(arguments), 1)
                self.process.assert_called_once()
        self.assertIn("no declarative disk layout", self.output.getvalue())

    def test_install_requires_exact_confirmation(self):
        with patch("builtins.input", return_value="yes"):
            self.assertEqual(deploy.main(["deploy", "guix-arm-builder"]), 1)
        self.process.assert_called_once()

    def test_arm_install_needs_no_private_key(self):
        with patch.dict(os.environ, {"HOME": "/tmp/deploy-test-home"}, clear=True):
            self.assertEqual(deploy.main(["deploy", "guix-arm-builder", "--yes"]), 0)
        command = self.process.call_args.args[0]
        self.assertEqual(command[:5], ["nix", "run", "--no-update-lock-file", ".#nixos-anywhere", "--"])
        self.assertNotIn("--extra-files", command)
        self.assertNotIn("--identity", command)
        self.assertEqual(command[command.index("-i") + 1], "/tmp/deploy-test-home/.ssh/guix-builder-aarch64.pem")
        self.assertEqual(self.process.call_count, 2)

    def test_key_staging_permissions_and_cleanup_after_install_failure(self):
        staged_directories = []
        def install(command, **kwargs):
            if command[0] == "age-keygen":
                return subprocess.CompletedProcess(command, 0, "age1expected\n")
            if command[:2] == ["nix", "run"]:
                directory = Path(command[command.index("--extra-files") + 1])
                staged_directories.append(directory)
                key = directory / "var/lib/sops-nix/key.txt"
                self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
                self.assertEqual(stat.S_IMODE(key.stat().st_mode), 0o600)
                self.assertEqual(key.read_bytes(), b"test private key")
                raise subprocess.CalledProcessError(5, command)
            return self.respond(command, **kwargs)
        self.process.side_effect = install
        with tempfile.TemporaryDirectory() as directory:
            key = Path(directory) / "identity"
            key.write_bytes(b"test private key")
            with patch.dict(os.environ, {"SOPS_KEY_FILE": str(key)}):
                self.assertEqual(deploy.main(["deploy", "nero", "--yes"]), 5)
        self.assertEqual(len(staged_directories), 1)
        self.assertFalse(staged_directories[0].exists())
        self.assertNotIn("test private key", self.output.getvalue())

    def test_wrong_recipient_aborts_before_install_and_cleans_up(self):
        staged_keys = []
        def mismatch(command, **kwargs):
            if command[0] == "age-keygen":
                staged_keys.append(Path(command[-1]))
                return subprocess.CompletedProcess(command, 0, "age1wrong\n")
            return self.respond(command, **kwargs)
        self.process.side_effect = mismatch
        with tempfile.NamedTemporaryFile() as key:
            with patch.dict(os.environ, {"SOPS_KEY_FILE": key.name}):
                self.assertEqual(deploy.main(["deploy", "nero", "--yes"]), 1)
        self.assertEqual(self.process.call_count, 2)
        self.assertFalse(staged_keys[0].exists())
        self.assertIn("does not match", self.output.getvalue())

    def test_ssh_identity_includes_derived_public_key(self):
        def install(command, **kwargs):
            if command[0] == "ssh-keygen":
                return subprocess.CompletedProcess(command, 0, "ssh-ed25519 test-public-key\n")
            if command[0] == "ssh-to-age":
                self.assertEqual(kwargs["input"], "ssh-ed25519 test-public-key\n")
                return subprocess.CompletedProcess(command, 0, "age1expected\n")
            if command[:2] == ["nix", "run"]:
                directory = Path(command[command.index("--extra-files") + 1])
                self.assertEqual((directory / "etc/ssh/ssh_host_ed25519_key.pub").read_text(), "ssh-ed25519 test-public-key\n")
                self.assertNotIn("--copy-host-keys", command)
                self.assertEqual(command[-2:], ["--kexec-extra-flags", "--kexec-syscall"])
                self.assertEqual(command[command.index("--target-host") + 1], "root@46.225.46.115")
            return self.respond(command, **kwargs)
        self.process.side_effect = install
        with tempfile.NamedTemporaryFile() as key:
            with patch.dict(os.environ, {"SOPS_KEY_FILE": key.name}):
                self.assertEqual(deploy.main(["deploy", "cdash-server", "--yes"]), 0)

    def test_reject_missing_and_repository_private_keys(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(deploy.main(["deploy", "nero", "--yes"]), 1)
        with patch.dict(os.environ, {"SOPS_KEY_FILE": str(Path(__file__).resolve())}):
            self.assertEqual(deploy.main(["deploy", "nero", "--yes"]), 1)
        self.assertEqual(self.process.call_count, 2)


if __name__ == "__main__":
    unittest.main()

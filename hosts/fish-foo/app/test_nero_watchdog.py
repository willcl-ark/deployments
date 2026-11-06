import subprocess
import unittest
from unittest.mock import patch

import nero_watchdog as monitor


class WatchdogTest(unittest.TestCase):
    def test_three_failures_repeat_and_recovery(self):
        messages = []
        state = {}
        for now in (0, 60):
            state = monitor.run_checks(state, now, lambda e: e[0] == "CDash", messages.append)
        self.assertEqual(messages, [])
        state = monitor.run_checks(state, 120, lambda e: e[0] == "CDash", messages.append)
        self.assertEqual(len(messages), 1)
        self.assertTrue(state["Nero"]["outage"])
        for endpoint in monitor.HOSTS["Nero"]:
            self.assertIn(endpoint[0], messages[0])
        state = monitor.run_checks(state, 3719, lambda e: e[0] == "CDash", messages.append)
        self.assertEqual(len(messages), 1)
        state = monitor.run_checks(state, 3720, lambda e: e[0] == "CDash", messages.append)
        self.assertEqual(len(messages), 2)
        state = monitor.run_checks(state, 3780, lambda _: True, messages.append)
        self.assertIn("recovered", messages[-1])
        self.assertFalse(state["Nero"]["outage"])
        state = monitor.run_checks(state, 3840, lambda _: True, messages.append)
        self.assertEqual(len(messages), 3)

    def test_failed_delivery_retries_outage_and_recovery(self):
        def fail(_):
            raise OSError("secret must not appear in output")

        state = monitor.run_checks({"Nero": {"failures": 2}}, 120,
                                   lambda e: e[0] == "CDash", fail)
        self.assertNotIn("outage", state["Nero"])
        messages = []
        state = monitor.run_checks(state, 180, lambda e: e[0] == "CDash", messages.append)
        self.assertTrue(state["Nero"]["outage"])
        state = monitor.run_checks(state, 240, lambda _: True, fail)
        self.assertTrue(state["Nero"]["outage"])
        state = monitor.run_checks(state, 300, lambda _: True, messages.append)
        self.assertFalse(state["Nero"]["outage"])
        self.assertEqual(len(messages), 2)

    def test_transient_failure_resets_and_all_endpoints_checked(self):
        checked = []
        def check(endpoint):
            checked.append(endpoint)
            raise ValueError("malformed response")
        state = monitor.run_checks({}, 0, check, self.fail)
        self.assertEqual(checked, [e for endpoints in monitor.HOSTS.values() for e in endpoints])
        self.assertEqual(state["Nero"]["failures"], 1)
        self.assertEqual(state["Kestrel"]["failures"], 1)
        state = monitor.run_checks(state, 60, lambda _: True, self.fail)
        self.assertEqual(state["Nero"]["failures"], 0)
        self.assertEqual(state["Kestrel"]["failures"], 0)

    def test_hosts_fail_and_recover_independently(self):
        messages = []
        state = {}
        for now in (0, 60):
            state = monitor.run_checks(state, now,
                                       lambda e: e[0] == "CDash", messages.append)
        state = monitor.run_checks(state, 120, lambda _: False, messages.append)
        self.assertEqual(len(messages), 1)
        self.assertIn("Nero outage", messages[0])
        self.assertEqual(state["Kestrel"]["failures"], 1)
        state = monitor.run_checks(state, 180, lambda e: e[0] != "CDash", messages.append)
        self.assertIn("Nero recovered", messages[-1])
        self.assertFalse(state["Nero"]["outage"])
        state = monitor.run_checks(state, 240, lambda e: e[0] != "CDash", messages.append)
        self.assertIn("Kestrel outage", messages[-1])
        self.assertNotIn("Forgejo", messages[-1])
        self.assertTrue(state["Kestrel"]["outage"])

    def test_delivery_failure_does_not_block_other_host(self):
        sent = []
        def send(message):
            if message.startswith("Nero"):
                raise OSError("failed")
            sent.append(message)
        state = {host: {"failures": 2} for host in monitor.HOSTS}
        state = monitor.run_checks(state, 120, lambda _: False, send)
        self.assertNotIn("outage", state["Nero"])
        self.assertTrue(state["Kestrel"]["outage"])
        self.assertEqual(len(sent), 1)
        self.assertIn("Kestrel outage", sent[0])
        state = monitor.run_checks(state, 180, lambda _: False, sent.append)
        self.assertTrue(state["Nero"]["outage"])
        self.assertEqual(len(sent), 2)

    def test_old_flat_state_is_discarded(self):
        state = monitor.run_checks({"failures": 20, "outage": True, "last_sent": 0},
                                   120, lambda _: False, self.fail)
        self.assertEqual(state, {host: {"failures": 1} for host in monitor.HOSTS})

    def test_cdash_https_status(self):
        endpoint = ("CDash", "cdash.fish.foo", "/", "http")
        for status in (b"200", b"201", b"204", b"301", b"404", b"500"):
            with self.subTest(status=status), patch.object(monitor.subprocess, "run") as run:
                run.return_value = subprocess.CompletedProcess([], 0, stdout=status)
                self.assertEqual(monitor.probe(endpoint), status == b"200")
                args = run.call_args.args[0]
                self.assertIn("https://cdash.fish.foo/", args)
                self.assertIn("--max-time", args)
                self.assertIn("--max-filesize", args)
                self.assertNotIn("--resolve", args)
                self.assertNotIn("--insecure", args)
                self.assertIn("--location", args)
                self.assertEqual(args[args.index("--max-redirs") + 1], "5")
                self.assertEqual(args[args.index("--proto-redir") + 1], "=https")
                self.assertIn("--output", args)
                self.assertEqual(args[args.index("--output") + 1], "/dev/null")
                self.assertLessEqual(run.call_args.kwargs["timeout"], 15)
        with patch.object(monitor.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 60, stdout=b"200")
            self.assertFalse(monitor.probe(endpoint))

    def test_nero_https_keeps_origin_override(self):
        def curl(args, **kwargs):
            self.assertIn("--resolve", args)
            self.assertIn(f"git.fish.foo:443:{monitor.ORIGIN}", args)
            self.assertNotIn("--insecure", args)
            kwargs["stdout"].write(b'{"status":"pass"}')
            return subprocess.CompletedProcess(args, 0)
        with patch.object(monitor.subprocess, "run", side_effect=curl):
            self.assertTrue(monitor.probe(monitor.HOSTS["Nero"][0]))

    def test_dns_validation(self):
        reply = b"status: NOERROR, flags: qr aa; QUERY: 1, ANSWER: 2"
        self.assertTrue(monitor.valid_body(reply, "dns"))
        for bad in (reply.replace(b"NOERROR", b"SERVFAIL"),
                    reply.replace(b" aa", b""),
                    reply.replace(b"ANSWER: 2", b"ANSWER: 0")):
            self.assertFalse(monitor.valid_body(bad, "dns"))

    def test_response_validation(self):
        self.assertTrue(monitor.valid_body(b'{"status":"pass"}', "forgejo"))
        self.assertFalse(monitor.valid_body(b'{"status":"fail"}', "forgejo"))
        self.assertTrue(monitor.valid_body(b"\x89PNG\r\n\x1a\nrest", "png"))
        self.assertFalse(monitor.valid_body(b"HTML", "png"))
        self.assertTrue(monitor.valid_body(b"StoreDir: /gnu/store\n", "/gnu/store"))
        self.assertFalse(monitor.valid_body(b"StoreDir: /nix/store\n", "/gnu/store"))


if __name__ == "__main__":
    unittest.main()

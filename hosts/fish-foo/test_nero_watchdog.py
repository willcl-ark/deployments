import unittest

import nero_watchdog as monitor


class WatchdogTest(unittest.TestCase):
    def test_three_failures_repeat_and_recovery(self):
        messages = []
        state = {}
        for now in (0, 60):
            state = monitor.run_checks(state, now, lambda _: False, messages.append)
        self.assertEqual(messages, [])
        state = monitor.run_checks(state, 120, lambda _: False, messages.append)
        self.assertEqual(len(messages), 1)
        self.assertTrue(state["outage"])
        for endpoint in monitor.ENDPOINTS:
            self.assertIn(endpoint[0], messages[0])
        state = monitor.run_checks(state, 3719, lambda _: False, messages.append)
        self.assertEqual(len(messages), 1)
        state = monitor.run_checks(state, 3720, lambda _: False, messages.append)
        self.assertEqual(len(messages), 2)
        state = monitor.run_checks(state, 3780, lambda _: True, messages.append)
        self.assertIn("recovered", messages[-1])
        self.assertFalse(state["outage"])
        state = monitor.run_checks(state, 3840, lambda _: True, messages.append)
        self.assertEqual(len(messages), 3)

    def test_failed_delivery_retries_outage_and_recovery(self):
        def fail(_):
            raise OSError("secret must not appear in output")

        state = monitor.run_checks({"failures": 2}, 120, lambda _: False, fail)
        self.assertNotIn("outage", state)
        messages = []
        state = monitor.run_checks(state, 180, lambda _: False, messages.append)
        self.assertTrue(state["outage"])
        state = monitor.run_checks(state, 240, lambda _: True, fail)
        self.assertTrue(state["outage"])
        state = monitor.run_checks(state, 300, lambda _: True, messages.append)
        self.assertFalse(state["outage"])
        self.assertEqual(len(messages), 2)

    def test_transient_failure_resets_and_all_endpoints_checked(self):
        checked = []
        def check(endpoint):
            checked.append(endpoint)
            raise ValueError("malformed response")
        state = monitor.run_checks({}, 0, check, self.fail)
        self.assertEqual(checked, list(monitor.ENDPOINTS))
        self.assertEqual(state["failures"], 1)
        state = monitor.run_checks(state, 60, lambda _: True, self.fail)
        self.assertEqual(state["failures"], 0)

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

import tempfile
from pathlib import Path
import unittest

import nero_commands as commands


def update(update_id=1, text="/status", user=448332502, chat=448332502):
    return {"update_id": update_id, "message": {"text": text,
            "from": {"id": user}, "chat": {"id": chat, "type": "private"}}}


class CommandsTest(unittest.TestCase):
    def test_authorization(self):
        sent = []
        group = update()
        group["message"]["chat"]["type"] = "group"
        for item in [update(user=1), update(chat=1),
                     group,
                     {"message": {"chat": [], "from": None}},
                     {"edited_message": update()["message"]}, {},
                     {"message": None}]:
            commands.reply(item, sent.append)
        self.assertEqual(sent, [])

    def test_help(self):
        self.assertIn("Nero and Kestrel", commands.HELP)
        for text in ["/help", "/start", "/unknown", "hello", ""]:
            sent = []
            commands.reply(update(text=text), sent.append)
            self.assertEqual(sent, [commands.HELP])

    def test_status(self):
        checked = []

        def check(endpoint):
            checked.append(endpoint)
            if endpoint[0] == "Forgejo":
                raise OSError("unreachable")
            return True

        sent = []
        commands.reply(update(), sent.append, check)
        self.assertEqual(checked, [e for endpoints in commands.watchdog.HOSTS.values() for e in endpoints])
        self.assertIn("UTC", sent[0])
        self.assertIn("Forgejo: FAILED", sent[0])
        self.assertIn("Ralph: healthy", sent[0])
        self.assertIn("\nNero:\nForgejo: FAILED", sent[0])
        self.assertIn("\nKestrel:\nCDash: healthy", sent[0])

    def test_healthy_status(self):
        text = commands.status(lambda endpoint: True)
        self.assertEqual(text.count(": healthy"), sum(map(len, commands.watchdog.HOSTS.values())))
        self.assertNotIn("FAILED", text)

    def test_partial_batch_preserves_progress(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "offset"
            sent = []

            def send(message):
                if sent:
                    raise OSError("send failed")
                sent.append(message)

            with self.assertRaises(OSError):
                commands.process_updates([update(1, "/help"), update(2, "/help")],
                                         0, path, send)
            self.assertEqual(path.read_text(), "2\n")
            commands.process_updates([update(1, "/help"), update(2, "/help")],
                                     2, path, sent.append)
            self.assertEqual(path.read_text(), "3\n")
            self.assertEqual(len(sent), 2)

    def test_offset_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "offset"

            def fail(message):
                raise OSError("send failed")

            with self.assertRaises(OSError):
                commands.process_updates([update(text="/help")], 0, path, fail)
            self.assertFalse(path.exists())
            sent = []
            offset = commands.process_updates([update(text="/help")], 0, path, sent.append)
            self.assertEqual(offset, 2)
            self.assertEqual(path.read_text(), "2\n")
            self.assertEqual(len(sent), 1)
            commands.process_updates([update(text="/help")], offset, path, sent.append)
            self.assertEqual(len(sent), 1)

    def test_ignored_updates_advance(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "offset"
            sent = []
            offset = commands.process_updates([update(user=1),
                       {"update_id": 2, "edited_message": update()["message"]},
                       {"update_id": 3, "message": None}], 0, path, sent.append)
            self.assertEqual(offset, 4)
            self.assertEqual(sent, [])


if __name__ == "__main__":
    unittest.main()

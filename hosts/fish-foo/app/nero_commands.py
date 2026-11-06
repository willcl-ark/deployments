"""Answer private Telegram availability queries from fish.foo."""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.request

import nero_watchdog as watchdog

HELP = "Nero and Kestrel monitoring from fish.foo:\n/status - fresh public endpoint checks\n/help - show commands\nChecks cover availability, not disk usage or Ralph worker progress."


def status(check=watchdog.probe):
    lines = ["Availability checked from fish.foo",
             datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")]
    for host, endpoints in watchdog.HOSTS.items():
        lines.extend(["", f"{host}:"])
        for endpoint in endpoints:
            try:
                healthy = check(endpoint)
            except (OSError, ValueError, AttributeError, subprocess.TimeoutExpired):
                healthy = False
            lines.append(f"{endpoint[0]}: {'healthy' if healthy else 'FAILED'}")
    return "\n".join(lines)


def reply(update, send, check=watchdog.probe):
    message = update.get("message")
    if not isinstance(message, dict):
        return
    chat = message.get("chat")
    sender = message.get("from")
    if not isinstance(chat, dict) or not isinstance(sender, dict):
        return
    if (chat.get("type") != "private" or chat.get("id") != int(watchdog.CHAT_ID)
            or sender.get("id") != int(watchdog.CHAT_ID)):
        return
    text = message.get("text")
    if not isinstance(text, str):
        return
    command = text.split(maxsplit=1)[0] if text.strip() else ""
    send(status(check) if command == "/status" else HELP)


def process_updates(updates, offset, path, send, check=watchdog.probe):
    for update in updates:
        if not isinstance(update, dict):
            continue
        update_id = update.get("update_id")
        if type(update_id) is not int or update_id < offset:
            continue
        # A failed reply leaves this update pending, including across restarts.
        reply(update, send, check)
        offset = update_id + 1
        temporary = path.with_suffix(".tmp")
        temporary.write_text(str(offset) + "\n")
        os.replace(temporary, path)
    return offset


def get_updates(token, offset):
    request = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/getUpdates",
        data=json.dumps({"offset": offset, "timeout": 30,
                         "allowed_updates": ["message"]}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=40) as response:
        result = json.load(response)
    if not result.get("ok") or not isinstance(result.get("result"), list):
        raise RuntimeError("Telegram polling failed")
    return result["result"]


def main():
    path = Path(os.environ["STATE_DIRECTORY"]) / "offset"
    try:
        offset = int(path.read_text())
    except FileNotFoundError:
        offset = 0
    token = (Path(os.environ["CREDENTIALS_DIRECTORY"]) / "telegram-token").read_text().strip()
    while True:
        try:
            updates = get_updates(token, offset)
            offset = process_updates(updates, offset, path,
                                     lambda message: watchdog.notify(token, message))
        except Exception:
            # Reload persisted progress if a later update in this batch failed.
            print("Telegram command processing failed; retrying in 5 seconds", flush=True)
            time.sleep(5)
            if path.exists():
                offset = int(path.read_text())


if __name__ == "__main__":
    main()

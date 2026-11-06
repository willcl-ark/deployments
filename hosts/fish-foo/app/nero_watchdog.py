"""Check Nero and Kestrel public services from an independent host."""

import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.request

ORIGIN = "157.180.56.194"
CHAT_ID = "448332502"
HOSTS = {
    "Nero": (
        ("Forgejo", "git.fish.foo", "/api/healthz", "forgejo"),
        ("Ralph", "review.fish.foo", "/assets/bitcoin/bitcoin/1.png", "png"),
        ("Guix cache", "guix.fish.foo", "/nix-cache-info", "/gnu/store"),
        ("Nix cache", "cache.nix.fish.foo", "/nix-cache-info", "/nix/store"),
        ("Bitcoin seed UDP", "seed.bitcoin.fish.foo", "", "dns"),
        ("Bitcoin seed TCP", "seed.bitcoin.fish.foo", "+tcp", "dns"),
        ("Signet seed UDP", "seed.signet.bitcoin.fish.foo", "", "dns"),
        ("Signet seed TCP", "seed.signet.bitcoin.fish.foo", "+tcp", "dns"),
    ),
    "Kestrel": (("CDash", "cdash.fish.foo", "/", "http"),),
}


def valid_body(body, kind):
    if kind == "dns":
        flags = re.search(rb"flags: ([^;]+);", body)
        answers = re.search(rb"ANSWER: (\d+)", body)
        return (b"status: NOERROR," in body and flags is not None
                and b"aa" in flags[1].split() and answers is not None
                and int(answers[1]) > 0)
    if kind == "png":
        return body.startswith(b"\x89PNG\r\n\x1a\n")
    if kind == "forgejo":
        return json.loads(body).get("status") == "pass"
    return f"StoreDir: {kind}" in body.decode().splitlines()


def probe(endpoint):
    name, host, path, kind = endpoint
    if kind == "dns":
        command = ["dig", f"@{ORIGIN}", host, "A", "+norecurse",
                   "+time=3", "+tries=1"]
        if path:
            command.append(path)
        result = subprocess.run(command, capture_output=True, timeout=5, check=False)
        return result.returncode == 0 and valid_body(result.stdout, kind)
    if kind == "http":
        result = subprocess.run(
            ["curl", "--silent", "--fail", "--noproxy", "*",
             "--max-time", "10", "--max-filesize", "1048576",
             "--location", "--max-redirs", "5", "--proto-redir", "=https",
             "--output", "/dev/null", "--write-out", "%{http_code}",
             f"https://{host}{path}"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=15, check=False,
        )
        return result.returncode == 0 and result.stdout == b"200"
    # Keep TLS verification and the public Host header while bypassing the CDN.
    with tempfile.TemporaryFile() as output:
        result = subprocess.run(
            ["curl", "--silent", "--fail", "--noproxy", "*",
             "--max-time", "10", "--max-filesize", "1048576",
             "--resolve", f"{host}:443:{ORIGIN}", f"https://{host}{path}"],
            stdout=output, stderr=subprocess.DEVNULL, timeout=15, check=False,
        )
        if result.returncode:
            return False
        output.seek(0)
        return valid_body(output.read(1048577), kind)


def transition(host, state, failures, now):
    """Return the next state and a notification awaiting successful delivery."""
    state = dict(state)
    state["failures"] = state.get("failures", 0) + 1 if failures else 0
    if failures:
        due = not state.get("outage") or now - state.get("last_sent", 0) >= 3600
        if state["failures"] >= 3 and due:
            return state, f"{host} outage detected from fish.foo:\n" + "\n".join(failures)
    elif state.get("outage"):
        return state, f"{host} recovered. All monitored endpoints are responding."
    return state, None


def notify(token, message):
    request = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=json.dumps({"chat_id": CHAT_ID, "text": message}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        if not json.load(response).get("ok"):
            raise RuntimeError("Telegram rejected notification")


def run_checks(state, now, check, send):
    next_state = {}
    for host, endpoints in HOSTS.items():
        failures = []
        for endpoint in endpoints:
            try:
                healthy = check(endpoint)
            except (OSError, ValueError, AttributeError, subprocess.TimeoutExpired):
                healthy = False
            if not healthy:
                failures.append(endpoint[0])
        host_state, message = transition(host, state.get(host, {}), failures, now)
        if message:
            try:
                send(message)
            except Exception:
                # Never log exceptions containing the Telegram URL and bot token.
                print("Telegram notification failed; will retry next check", flush=True)
            else:
                host_state["outage"] = bool(failures)
                host_state["last_sent"] = now
        if failures:
            print(f"{host} unhealthy endpoints: " + ", ".join(failures), flush=True)
        next_state[host] = host_state
    return next_state


def main():
    state_path = Path(os.environ["STATE_DIRECTORY"]) / "state.json"
    try:
        state = json.loads(state_path.read_text())
    except FileNotFoundError:
        state = {}
    token = (Path(os.environ["CREDENTIALS_DIRECTORY"]) / "telegram-token").read_text().strip()
    state = run_checks(state, time.time(), probe, lambda message: notify(token, message))
    temporary = state_path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state) + "\n")
    os.replace(temporary, state_path)


if __name__ == "__main__":
    main()

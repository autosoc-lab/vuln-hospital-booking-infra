#!/usr/bin/env python3
import hashlib
import json
import os
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

WEBHOOK_URL = os.environ.get("DISCORD_WEBHOOK_URL", "")
TTL_SECONDS = int(os.environ.get("DISCORD_DEDUP_TTL_SECONDS", "600"))
STATE_FILE = os.environ.get("DISCORD_DEDUP_STATE_FILE", "/tmp/discord-alert-dedup.json")


def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state):
    tmp = f"{STATE_FILE}.tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE_FILE)


def dedup_key(alert):
    rule = alert.get("rule") or {}
    agent = alert.get("agent") or {}
    rule_id = str(rule.get("id") or "unknown_rule")
    agent_id = str(agent.get("id") or agent.get("name") or "unknown_agent")
    return f"{rule_id}:{agent_id}"


def should_send(alert):
    now = time.time()
    state = {
        key: ts for key, ts in load_state().items()
        if now - float(ts) < TTL_SECONDS
    }
    key = dedup_key(alert)
    if key in state:
        save_state(state)
        return False, key
    state[key] = now
    save_state(state)
    return True, key


def discord_content(alert):
    rule = alert.get("rule") or {}
    level = rule.get("level", "")
    description = rule.get("description") or "Wazuh alert"
    return f"🚨 CRITICAL [level {level}] {description}"


def post_discord(content):
    body = json.dumps({"content": content}).encode()
    request = urllib.request.Request(
        WEBHOOK_URL,
        data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return response.status, response.read().decode(errors="replace")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_POST(self):
        if self.path != "/alert/discord":
            self.send_response(404)
            self.end_headers()
            return

        length = int(self.headers.get("content-length", "0"))
        try:
            alert = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"invalid json")
            return

        with open("/tmp/discord-alert-last.json", "w") as f:
            json.dump(alert, f, ensure_ascii=False, indent=2)

        send, key = should_send(alert)
        if not send:
            self.send_response(202)
            self.end_headers()
            self.wfile.write(f"dedup skipped: {key}".encode())
            return

        if not WEBHOOK_URL:
            self.send_response(202)
            self.end_headers()
            self.wfile.write(b"discord webhook not configured")
            return

        try:
            status, body = post_discord(discord_content(alert))
        except urllib.error.HTTPError as e:
            status = e.code
            body = e.read().decode(errors="replace")
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())
            return

        self.send_response(200 if 200 <= status < 300 else 502)
        self.end_headers()
        self.wfile.write(f"discord status={status} key={key} {body}".encode())


if __name__ == "__main__":
    port = int(os.environ.get("DISCORD_ALERT_PORT", "8089"))
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()

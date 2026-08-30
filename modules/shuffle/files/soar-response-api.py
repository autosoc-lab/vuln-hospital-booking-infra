#!/usr/bin/env python3
import json
import os
import re
import secrets
import subprocess
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROUTES = {
    "/respond/ssh-compromise": {
        "script": os.environ.get(
            "SOAR_RESPONSE_SCRIPT", "/opt/soar/scripts/respond-ssh-compromise.sh"
        ),
        "rule_ids": {"100174", "100179", "100180"},
        "min_level": 15,
        "require_group": "hospital_ssh_compromise",
        "lock": "/tmp/soar-ssh-compromise-response.lock",
    },
    # SSE-C 랜섬웨어 체인 - lifecycle 원복. 되돌리기 쉽고 부작용이 거의 없는 조치라
    # 레벨과 무관하게(100031은 level 10) 승인 없이 자동 실행한다.
    "/respond/lifecycle-revert": {
        "script": "/opt/soar/scripts/respond-lifecycle-revert.sh",
        "rule_ids": {"100031", "100032"},
        "min_level": 0,
        "require_group": None,
        "lock": None,
    },
    # SSRF->IMDS 탈취 / SSE-C 반출 - STS 세션 revoke. 앱 EC2가 완전히 막히는
    # 부작용이 있는 조치라 100014/100034(확증, 승인 불필요)만 여기로 바로 연결돼있다.
    # 100013/100033(미확증, 승인 필요)은 아래 APPROVAL_ROUTES를 거쳐서 도착한다.
    "/respond/session-revoke": {
        "script": "/opt/soar/scripts/respond-session-revoke.sh",
        "rule_ids": {"100013", "100014", "100033", "100034"},
        "min_level": 0,
        "require_group": None,
        "lock": None,
    },
}

# 승인이 필요한 조치. Shuffle은 확증 전 단계(100013/100033)를 여기로 보낸다.
# 즉시 실행하지 않고 대기 토큰을 발급 -> Discord로 승인 링크 전송 -> 사람이 링크를
# 클릭해야(GET /respond/<action>/approve/<token>) 실제 스크립트가 돈다.
APPROVAL_ROUTES = {
    "/respond/session-revoke/request": {
        "action": "session-revoke",
        "script": "/opt/soar/scripts/respond-session-revoke.sh",
        "rule_ids": {"100013", "100033"},
        "min_level": 0,
        "require_group": None,
    },
}

PENDING_DIR = "/tmp"
TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{16,64}$")
APPROVAL_TTL_SECONDS = int(os.environ.get("SOAR_APPROVAL_TTL_SECONDS", "1800"))
DISCORD_WEBHOOK_URL = os.environ.get("DISCORD_WEBHOOK_URL", "")
PUBLIC_BASE_URL = os.environ.get("SOAR_PUBLIC_BASE_URL", "").rstrip("/")


def should_respond(route, alert):
    rule = alert.get("rule") or {}
    rule_id = str(rule.get("id") or "")
    level = int(rule.get("level") or 0)
    groups = set(rule.get("groups") or [])

    if route["require_group"] and route["require_group"] not in groups:
        return False
    if level < route["min_level"]:
        return False
    return rule_id in route["rule_ids"]


def pending_path(token):
    return os.path.join(PENDING_DIR, f"soar-pending-{token}.json")


def notify_discord(text):
    if not DISCORD_WEBHOOK_URL:
        return
    body = json.dumps({"content": text}).encode()
    req = urllib.request.Request(
        DISCORD_WEBHOOK_URL,
        data=body,
        headers={"content-type": "application/json"},
        method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=5).read()
    except (urllib.error.URLError, urllib.error.HTTPError):
        pass


def create_pending(approval_route, alert):
    token = secrets.token_urlsafe(24)
    now = time.time()
    record = {
        "token": token,
        "action": approval_route["action"],
        "script": approval_route["script"],
        "alert": alert,
        "created_at": now,
        "expires_at": now + APPROVAL_TTL_SECONDS,
        "used": False,
    }
    with open(pending_path(token), "w") as f:
        json.dump(record, f, ensure_ascii=False, indent=2)
    return token


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _respond(self, code, body=b""):
        self.send_response(code)
        self.end_headers()
        if body:
            self.wfile.write(body if isinstance(body, bytes) else body.encode())

    def _run_script(self, script, alert, tag):
        with open(f"/tmp/soar-last-{tag}-alert.json", "w") as f:
            json.dump(alert, f, ensure_ascii=False, indent=2)
        proc = subprocess.run([script], text=True, capture_output=True)
        with open(f"/tmp/soar-last-{tag}-response.log", "w") as f:
            f.write(proc.stdout)
            f.write(proc.stderr)
        return proc

    def do_POST(self):
        route = ROUTES.get(self.path)
        if route is not None:
            self._handle_direct(route)
            return

        approval_route = APPROVAL_ROUTES.get(self.path)
        if approval_route is not None:
            self._handle_approval_request(approval_route)
            return

        self._respond(404)

    def _handle_direct(self, route):
        length = int(self.headers.get("content-length", "0"))
        try:
            alert = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._respond(400, "invalid json")
            return

        if not should_respond(route, alert):
            self._respond(202, "ignored")
            return

        lock = route["lock"]
        if lock and os.path.exists(lock):
            self._respond(202, "already handled")
            return
        if lock:
            open(lock, "w").close()

        tag = self.path.strip("/").replace("/", "-")
        proc = None
        try:
            proc = self._run_script(route["script"], alert, tag)
        finally:
            if lock and (proc is None or proc.returncode != 0):
                try:
                    os.remove(lock)
                except FileNotFoundError:
                    pass

        self._respond(200 if proc.returncode == 0 else 500, proc.stdout + proc.stderr)

    def _handle_approval_request(self, approval_route):
        length = int(self.headers.get("content-length", "0"))
        try:
            alert = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._respond(400, "invalid json")
            return

        if not should_respond(approval_route, alert):
            self._respond(202, "ignored")
            return

        token = create_pending(approval_route, alert)
        rule = alert.get("rule") or {}
        approve_url = f"{PUBLIC_BASE_URL}/respond/{approval_route['action']}/approve/{token}"
        minutes = APPROVAL_TTL_SECONDS // 60
        notify_discord(
            "⏸️ **승인 대기: 세션 revoke 필요**\n"
            f"rule.id={rule.get('id')} level={rule.get('level')}\n"
            f"{rule.get('description', '')}\n"
            f"{minutes}분 안에 승인하세요: {approve_url}"
        )
        self._respond(200, json.dumps({"status": "pending", "token": token}))

    def do_GET(self):
        m = re.match(r"^/respond/([a-z-]+)/approve/([A-Za-z0-9_-]+)$", self.path)
        if not m:
            self._respond(404)
            return

        action, token = m.group(1), m.group(2)
        if not TOKEN_RE.match(token):
            self._respond(400, "malformed token")
            return

        path = pending_path(token)
        if not os.path.isfile(path):
            self._respond(404, "unknown or expired token")
            return

        with open(path) as f:
            record = json.load(f)

        if record.get("action") != action:
            self._respond(404, "unknown token")
            return
        if record.get("used"):
            self._respond(409, "already approved and executed")
            return
        if time.time() > record.get("expires_at", 0):
            self._respond(410, "approval window expired - wait for a new Wazuh alert")
            return

        record["used"] = True
        with open(path, "w") as f:
            json.dump(record, f, ensure_ascii=False, indent=2)

        tag = f"{action}-approved-{token[:8]}"
        proc = self._run_script(record["script"], record["alert"], tag)
        notify_discord(
            f"✅ 승인 처리 완료: {action} (rule.id={record['alert'].get('rule', {}).get('id')})"
        )
        self._respond(200 if proc.returncode == 0 else 500, proc.stdout + proc.stderr)


if __name__ == "__main__":
    port = int(os.environ.get("SOAR_RESPONSE_PORT", "8088"))
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()

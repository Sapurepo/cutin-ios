#!/usr/bin/env python3
"""알림·디바이스 검증용 스텁 서버.

서버의 제약을 그대로 흉내낸다:

- `POST /notifications/read`의 `ids`는 **한 번에 100개까지**(`maxItems`)
- `PUT /users/me/notification-preferences`의 `slots`는 **하나 이상**(`minItems: 1`)
- `GET /notifications/unread-count`가 따로 있다 — 목록에서 세면 받아 온 페이지 안에서만 참이다

미읽음 수를 목록과 **따로** 관리한다. 앱이 목록에서 세는 실수를 하면 값이 갈리도록.
"""
import json, sys, threading, uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8771
PAGE_SIZE = 2
MAX_READ_IDS = 100

notifications = []     # 오래된 → 최신
devices = {}           # pushToken -> device
prefs = {"slots": ["morning"], "pushEnabled": True}

state = {
    "readCount": 0, "readIdCount": 0, "maxIdsInOneCall": 0,
    "deviceRegisterCount": 0, "deviceRevokeCount": 0,
    "prefsPutCount": 0, "lastPrefs": None, "lastDevice": None,
    "seedNotifications": 0, "seedUnread": 0,
}
lock = threading.Lock()


def now(offset=0):
    return (datetime.now(timezone.utc) + timedelta(seconds=offset)).isoformat()


def unread_count():
    return sum(1 for item in notifications if item["readAt"] is None)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _no_content(self):
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _error(self, code, name, message):
        self._send(code, {"error": {"code": name, "message": message}})

    def _authorized(self):
        return self.headers.get("Authorization") == "Bearer GOOD"

    def _raw(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def _json(self):
        try:
            return json.loads(self._raw() or b"{}")
        except Exception:
            return {}

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/__state":
            with lock:
                self._send(200, dict(state))
            return
        if parsed.path == "/health":
            self._send(200, {"status": "ok", "database": "up"})
            return
        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return

        cursor = (parse_qs(parsed.query).get("cursor") or [None])[0]

        with lock:
            if parsed.path == "/notifications":
                ordered = list(reversed(notifications))   # 최신 → 오래된
                start = 0
                if cursor:
                    ids = [n["id"] for n in ordered]
                    start = ids.index(cursor) + 1 if cursor in ids else 0
                window = ordered[start:start + PAGE_SIZE]
                tail = ordered[start + PAGE_SIZE:]
                self._send(200, {"items": window,
                                 "nextCursor": window[-1]["id"] if window and tail else None})
                return
            if parsed.path == "/notifications/unread-count":
                self._send(200, {"count": unread_count()})
                return
            if parsed.path == "/users/me/notification-preferences":
                self._send(200, dict(prefs))
                return
            if parsed.path == "/users/me":
                self._send(200, {"id": "3f2c1b4a-5d6e-4f70-8a9b-0c1d2e3f4a5b",
                                 "nickname": "네컷러버", "avatarUrl": None,
                                 "timezone": "Asia/Seoul", "onboardingCompleted": True})
                return

        self._error(404, "NOT_FOUND", "없음")

    def do_PUT(self):
        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return
        if self.path != "/users/me/notification-preferences":
            self._error(404, "NOT_FOUND", "없음")
            return

        body = self._json()
        with lock:
            state["prefsPutCount"] += 1
            state["lastPrefs"] = body
            slots = body.get("slots") or []
            # 슬롯은 하나 이상이어야 한다. 앱이 마지막 하나를 끄려 하면 여기서 걸린다.
            if not slots:
                self._error(400, "VALIDATION_FAILED", "시간대를 하나 이상 선택해주세요.")
                return
            prefs["slots"] = slots
            prefs["pushEnabled"] = body.get("pushEnabled", True)
            self._send(200, dict(prefs))

    def do_POST(self):
        if self.path == "/__reset":
            patch = self._json()
            with lock:
                notifications.clear(); devices.clear()
                prefs.update({"slots": ["morning"], "pushEnabled": True})
                state.update({
                    "readCount": 0, "readIdCount": 0, "maxIdsInOneCall": 0,
                    "deviceRegisterCount": 0, "deviceRevokeCount": 0,
                    "prefsPutCount": 0, "lastPrefs": None, "lastDevice": None,
                    "seedNotifications": 0, "seedUnread": 0,
                })
                state.update(patch)
                for index in range(state["seedNotifications"]):
                    unread = index >= state["seedNotifications"] - state["seedUnread"]
                    notifications.append({
                        "id": str(uuid.uuid4()),
                        "type": ["comment", "reaction", "follow"][index % 3],
                        "actor": {"id": str(uuid.uuid4()),
                                  "nickname": f"친구{index}", "avatarUrl": None},
                        "targetType": "post" if index % 2 == 0 else "user",
                        "targetId": str(uuid.uuid4()),
                        "readAt": None if unread else now(-100),
                        "createdAt": now(index),
                    })
            self._send(200, {"ok": True})
            return

        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return

        if self.path == "/notifications/read":
            body = self._json()
            ids = body.get("ids") or []
            with lock:
                state["readCount"] += 1
                state["readIdCount"] += len(ids)
                state["maxIdsInOneCall"] = max(state["maxIdsInOneCall"], len(ids))
                if not ids or len(ids) > MAX_READ_IDS:
                    self._error(400, "VALIDATION_FAILED", "한 번에 100개까지 처리할 수 있어요.")
                    return
                wanted = {str(i).lower() for i in ids}
                for item in notifications:
                    if item["id"] in wanted and item["readAt"] is None:
                        item["readAt"] = now()
            self._no_content()
            return

        if self.path == "/devices":
            body = self._json()
            with lock:
                state["deviceRegisterCount"] += 1
                state["lastDevice"] = body
                token = body.get("pushToken")
                if not token:
                    self._error(400, "VALIDATION_FAILED", "pushToken이 필요합니다.")
                    return
                device = {"id": str(uuid.uuid4()), "platform": body.get("platform"),
                          "timezone": body.get("timezone")}
                devices[token] = device
            self._send(201, device)
            return

        if self.path == "/auth/logout":
            self._raw()
            self._send(200, {"ok": True})
            return

        self._error(404, "NOT_FOUND", "없음")

    def do_DELETE(self):
        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return
        if self.path == "/devices":
            body = self._json()
            with lock:
                state["deviceRevokeCount"] += 1
                devices.pop(body.get("pushToken"), None)
            self._no_content()
            return
        self._error(404, "NOT_FOUND", "없음")


if __name__ == "__main__":
    print(f"알림 스텁 :{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

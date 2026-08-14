#!/usr/bin/env python3
"""인증 흐름 검증용 스텁 서버.

카카오 로그인은 사람이 눌러야 해서 자동화할 수 없지만, **위험한 로직은 로그인 이후**에 있다:
401 → 재발급 → 재시도, 동시 401의 직렬화, 재발급 실패 시 로그아웃. 그것을 실제 HTTP로 돌린다.

스레딩 서버인 이유: 단일 스레드면 동시 요청이 줄을 서서 "재발급이 한 번만 일어나는가"를
시험할 수 없다(경쟁이 아예 생기지 않으므로 통과가 무의미해진다).
"""
import json, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765

state = {
    "expectedAccess": "GOOD",   # 이 값과 다른 Bearer는 401
    "nextAccess": "GOOD2",      # 재발급이 내놓을 새 액세스 토큰
    "refreshShouldFail": False,
    "refreshCount": 0,
    "refreshDelay": 0.25,       # 경쟁 창을 넓힌다
    "meCount": 0,
}
lock = threading.Lock()

PROFILE = {
    "id": "3f2c1b4a-5d6e-4f70-8a9b-0c1d2e3f4a5b",
    "nickname": "네컷러버",
    "avatarUrl": None,
    "timezone": "Asia/Seoul",
    "onboardingCompleted": True,
}
TEMPLATES = {"items": []}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass  # 조용히

    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _unauthorized(self):
        self._send(401, {"error": {"code": "UNAUTHORIZED", "message": "인증이 필요합니다."}})

    def _authorized(self):
        header = self.headers.get("Authorization", "")
        with lock:
            expected = state["expectedAccess"]
        return header == f"Bearer {expected}"

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            return json.loads(raw)
        except Exception:
            return {}

    def do_GET(self):
        if self.path == "/__state":
            with lock:
                self._send(200, dict(state))
            return
        if self.path in ("/users/me", "/templates"):
            if not self._authorized():
                self._unauthorized(); return
            if self.path == "/users/me":
                with lock:
                    state["meCount"] += 1
                self._send(200, PROFILE)
            else:
                self._send(200, TEMPLATES)
            return
        self._send(404, {"error": {"code": "NOT_FOUND", "message": "없음"}})

    def do_POST(self):
        if self.path == "/__reset":
            patch = self._body()
            with lock:
                state.update(patch)
                state["refreshCount"] = 0
                state["meCount"] = 0
            self._send(200, {"ok": True})
            return

        if self.path == "/auth/refresh":
            body = self._body()
            time.sleep(state["refreshDelay"])
            with lock:
                state["refreshCount"] += 1
                fail = state["refreshShouldFail"]
                new_access = state["nextAccess"]
                if not fail:
                    state["expectedAccess"] = new_access
            if fail:
                self._send(401, {"error": {"code": "UNAUTHORIZED",
                                           "message": "리프레시 토큰이 만료되었습니다."}})
                return
            if not body.get("refreshToken"):
                self._send(400, {"error": {"code": "VALIDATION_FAILED",
                                           "message": "refreshToken이 필요합니다."}})
                return
            self._send(200, {"accessToken": new_access,
                             "refreshToken": "R-" + new_access,
                             "expiresIn": 3600})
            return

        if self.path == "/auth/logout":
            self._send(200, {"ok": True}); return

        if self.path.startswith("/auth/oauth/"):
            self._send(200, {"accessToken": "GOOD", "refreshToken": "R1",
                             "expiresIn": 3600, "onboardingCompleted": True})
            return

        self._send(404, {"error": {"code": "NOT_FOUND", "message": "없음"}})


if __name__ == "__main__":
    print(f"스텁 서버 :{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

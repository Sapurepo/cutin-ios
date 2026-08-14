#!/usr/bin/env python3
"""온보딩(§3.1) 검증용 스텁 서버.

닉네임 확인은 눈으로 볼 수 있지만, **틀리면 조용히 막히는 것은 저장 쪽**이다:
- `POST /users/me/onboarding/complete`는 닉네임이 없으면 거절한다(`NICKNAME_REQUIRED`)
- 서버의 `isNicknameTaken`이 **자기 자신을 제외하지 않아서**, 이미 저장한 이름을 다시 보내면
  자기 이름에 409가 난다. 첫 왕복만 성공하고 둘째가 끊긴 뒤 재시도하는 경로가 그 상황이다.

그래서 이 스텁은 실제 백엔드(`usersService.ts`)의 **거절 조건을 그대로 흉내낸다.** 관대하게
만들면 앱이 함정을 피하는지 시험할 수 없다.
"""
import json, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8767

# 실제 서버가 쓰는 것과 같은 규칙 (usersSchemas.ts · nicknamePolicy.ts)
FORBIDDEN = ["admin", "administrator", "cutin", "official", "운영자", "관리자", "컷인"]
TAKEN = {"이미쓰는이름"}

state = {
    "nickname": None,          # 서버에 저장된 내 닉네임
    "onboardingCompleted": False,
    "availabilityCount": 0,
    "patchCount": 0,
    "completeCount": 0,
    "lastNickname": None,      # 확인 요청이 마지막으로 받은 값
    "lastTimezone": None,      # PATCH가 마지막으로 받은 값
    "completeShouldFail": False,
    # 스펙에 없는 사유를 내보낸다 — 앱이 던지지 않고 견디는지 본다
    "unknownReason": False,
}
lock = threading.Lock()


def profile():
    return {
        "id": "3f2c1b4a-5d6e-4f70-8a9b-0c1d2e3f4a5b",
        "nickname": state["nickname"],
        "avatarUrl": None,
        "timezone": state["lastTimezone"] or "Asia/Seoul",
        "onboardingCompleted": state["onboardingCompleted"],
    }


def is_valid(nickname):
    """길이 2~16 · 한글·영문·숫자·밑줄. 서버 `nicknameSchema`와 같다."""
    if not (2 <= len(nickname) <= 16):
        return False
    return all(
        c == "_" or c.isdigit() or ("a" <= c.lower() <= "z") or "가" <= c <= "힣"
        for c in nickname
    )


def is_forbidden(nickname):
    lowered = nickname.lower()
    return any(word in lowered for word in FORBIDDEN)


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

    def _error(self, code, name, message):
        self._send(code, {"error": {"code": name, "message": message}})

    def _authorized(self):
        return self.headers.get("Authorization") == "Bearer GOOD"

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            return json.loads(self.rfile.read(length) if length else b"{}")
        except Exception:
            return {}

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/__state":
            with lock:
                self._send(200, dict(state))
            return

        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return

        if parsed.path == "/users/me":
            with lock:
                self._send(200, profile())
            return

        if parsed.path == "/users/nickname/availability":
            nickname = (parse_qs(parsed.query).get("nickname") or [""])[0]
            with lock:
                state["availabilityCount"] += 1
                state["lastNickname"] = nickname
                unknown = state["unknownReason"]
            if unknown:
                # 서버가 사유를 새로 추가한 미래. 앱은 던지지 않고 일반 문구로 떨어져야 한다.
                self._send(200, {"available": False, "reason": "reserved"})
            elif not is_valid(nickname):
                self._send(200, {"available": False, "reason": "invalidFormat"})
            elif is_forbidden(nickname):
                self._send(200, {"available": False, "reason": "forbiddenWord"})
            elif nickname in TAKEN or nickname == state["nickname"]:
                # 자기 자신도 taken으로 본다 — 실제 서버가 그렇다.
                self._send(200, {"available": False, "reason": "taken"})
            else:
                self._send(200, {"available": True, "reason": None})
            return

        self._error(404, "NOT_FOUND", "없음")

    def do_PATCH(self):
        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return
        if self.path != "/users/me":
            self._error(404, "NOT_FOUND", "없음")
            return

        body = self._body()
        with lock:
            state["patchCount"] += 1
            if "timezone" in body:
                state["lastTimezone"] = body["timezone"]
            nickname = body.get("nickname")
            if nickname is not None:
                if is_forbidden(nickname):
                    self._error(400, "NICKNAME_FORBIDDEN", "사용할 수 없는 닉네임입니다.")
                    return
                # 자기 자신을 제외하지 않는다 — 실제 서버의 `isNicknameTaken` 그대로다.
                if nickname in TAKEN or nickname == state["nickname"]:
                    self._error(409, "NICKNAME_TAKEN", "이미 사용 중인 닉네임입니다.")
                    return
                state["nickname"] = nickname
            self._send(200, profile())

    def do_POST(self):
        if self.path == "/__reset":
            patch = self._body()
            with lock:
                state.update({
                    "nickname": None, "onboardingCompleted": False,
                    "availabilityCount": 0, "patchCount": 0, "completeCount": 0,
                    "lastNickname": None, "lastTimezone": None,
                    "completeShouldFail": False, "unknownReason": False,
                })
                state.update(patch)
            self._send(200, {"ok": True})
            return

        # 카운터를 지우지 않고 상태만 바꾼다 — "실패한 뒤 다시 시도" 시나리오가 필요로 한다.
        if self.path == "/__set":
            with lock:
                state.update(self._body())
            self._send(200, {"ok": True})
            return

        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return

        if self.path == "/users/me/onboarding/complete":
            with lock:
                state["completeCount"] += 1
                if state["completeShouldFail"]:
                    self._error(500, "INTERNAL_ERROR", "일시적인 오류입니다.")
                    return
                if state["nickname"] is None:
                    self._error(400, "NICKNAME_REQUIRED", "닉네임을 먼저 설정해야 합니다.")
                    return
                state["onboardingCompleted"] = True
                self._send(200, profile())
            return

        if self.path == "/auth/logout":
            self._send(200, {"ok": True})
            return

        self._error(404, "NOT_FOUND", "없음")


if __name__ == "__main__":
    print(f"온보딩 스텁 :{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

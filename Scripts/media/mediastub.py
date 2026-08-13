#!/usr/bin/env python3
"""미디어 업로드 검증용 스텁 서버.

업로드는 왕복이 셋이고 **순서를 틀리면 조용히 아프다**:

- ③ `complete`를 빠뜨린 미디어는 pending으로 남고, 서버는 pending 미디어를 포스트·프로필에
  붙이지 못하게 막는다(`findReadyByIds`). 화면에는 "업로드는 됐는데 안 붙는다"로 보인다.
- ② `PUT`이 `[auth]`라 Bearer가 필요하다. `POST /media/uploads`가 준 `headers`만 싣고 인증을
  빠뜨리면 401이다.

그래서 이 스텁은 실제 서버처럼 **상태 기계**로 만든다: 바이트가 오기 전에 complete하면 거절하고,
ready가 아닌 미디어를 프로필에 붙이면 400을 낸다.
"""
import json, sys, threading, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8768
MAX_UPLOAD_BYTES = 15 * 1024 * 1024   # 서버 appSetup.ts와 같은 값

state = {
    "createCount": 0,
    "putCount": 0,
    "completeCount": 0,
    "patchCount": 0,
    "lastKind": None,
    "lastMime": None,
    "lastContentType": None,
    "lastAuthorized": None,   # PUT에 Bearer가 붙었는지
    "lastBytes": 0,
    "lastWidth": None,
    "lastHeight": None,
    "avatarUrl": None,
    # 첫 PUT을 401로 돌려보낸다 — 재발급 후 재시도가 도는지 본다
    "putUnauthorizedOnce": False,
    "refreshCount": 0,
    "expectedAccess": "GOOD",
}
media = {}       # id -> {kind, status, width, height}
content = {}     # path -> bytes
lock = threading.Lock()


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
        with lock:
            expected = state["expectedAccess"]
        return self.headers.get("Authorization") == f"Bearer {expected}"

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def _json(self):
        try:
            return json.loads(self._body() or b"{}")
        except Exception:
            return {}

    def _profile(self):
        return {
            "id": "3f2c1b4a-5d6e-4f70-8a9b-0c1d2e3f4a5b",
            "nickname": "네컷러버",
            "avatarUrl": state["avatarUrl"],
            "timezone": "Asia/Seoul",
            "onboardingCompleted": True,
        }

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/__state":
            with lock:
                self._send(200, dict(state))
            return
        if parsed.path == "/users/me":
            if not self._authorized():
                self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
                return
            with lock:
                self._send(200, self._profile())
            return
        # 이미지 조회는 인증을 요구하지 않는다 (계약에 그렇게 적혀 있다)
        if parsed.path.startswith("/media/content/"):
            key = parsed.path[len("/media/content/"):]
            with lock:
                blob = content.get(key)
            if blob is None:
                self._error(404, "NOT_FOUND", "없음")
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(blob)))
            self.end_headers()
            self.wfile.write(blob)
            return
        self._error(404, "NOT_FOUND", "없음")

    def do_PUT(self):
        parsed = urlparse(self.path)
        if not parsed.path.startswith("/media/content/"):
            self._error(404, "NOT_FOUND", "없음")
            return

        raw = self._body()
        # 락 밖에서 판정한다 — `_authorized()`가 같은 락을 잡으므로 안에서 부르면 데드락이다.
        authorized = self._authorized()
        with lock:
            state["putCount"] += 1
            state["lastAuthorized"] = authorized
            state["lastContentType"] = self.headers.get("Content-Type")
            state["lastBytes"] = len(raw)
            once = state["putUnauthorizedOnce"]
            if once:
                # 한 번만 401. 재발급 → 재시도가 도는지 보기 위한 것이다.
                state["putUnauthorizedOnce"] = False
        if once:
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return
        if not authorized:
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return
        if len(raw) > MAX_UPLOAD_BYTES:
            self._error(413, "PAYLOAD_TOO_LARGE", "업로드 용량이 너무 큽니다.")
            return

        key = parsed.path[len("/media/content/"):]
        with lock:
            content[key] = raw
            for item in media.values():
                if item["key"] == key:
                    item["uploaded"] = True
        self._send(200, {"ok": True})

    def do_PATCH(self):
        if self.path != "/users/me":
            self._error(404, "NOT_FOUND", "없음")
            return
        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return
        body = self._json()
        with lock:
            state["patchCount"] += 1
            if "avatarMediaId" in body:
                target = body["avatarMediaId"]
                if target is None:
                    state["avatarUrl"] = None
                else:
                    item = media.get(str(target).lower())
                    # 실제 서버와 같은 조건: ready이고 kind가 avatar인 내 미디어만.
                    if item is None or item["status"] != "ready" or item["kind"] != "avatar":
                        self._error(400, "MEDIA_NOT_READY", "프로필 사진 업로드가 끝나지 않았습니다.")
                        return
                    state["avatarUrl"] = f"http://127.0.0.1:{PORT}/media/content/{item['key']}"
            self._send(200, self._profile())

    def do_POST(self):
        if self.path == "/__reset":
            patch = self._json()
            with lock:
                media.clear()
                content.clear()
                state.update({
                    "createCount": 0, "putCount": 0, "completeCount": 0, "patchCount": 0,
                    "lastKind": None, "lastMime": None, "lastContentType": None,
                    "lastAuthorized": None, "lastBytes": 0,
                    "lastWidth": None, "lastHeight": None, "avatarUrl": None,
                    "putUnauthorizedOnce": False, "refreshCount": 0, "expectedAccess": "GOOD",
                })
                state.update(patch)
            self._send(200, {"ok": True})
            return

        if self.path == "/auth/refresh":
            # 본문을 반드시 비운다. 안 읽으면 keep-alive 소켓에 남아 다음 요청 앞에 붙는다
            # (`{"refreshToken":"R1"}PUT /media/...`로 파싱돼 501이 났다).
            self._body()
            with lock:
                state["refreshCount"] += 1
                state["expectedAccess"] = "GOOD2"
            self._send(200, {"accessToken": "GOOD2", "refreshToken": "R2", "expiresIn": 3600})
            return

        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return

        if self.path == "/media/uploads":
            body = self._json()
            kind, mime = body.get("kind"), body.get("mime")
            if kind not in ("cut", "composed", "avatar"):
                self._error(400, "VALIDATION_FAILED", "kind가 올바르지 않습니다.")
                return
            media_id = str(uuid.uuid4())
            key = f"{kind}/{media_id}.jpg"
            with lock:
                state["createCount"] += 1
                state["lastKind"], state["lastMime"] = kind, mime
                media[media_id] = {"kind": kind, "status": "pending",
                                   "key": key, "uploaded": False}
            self._send(201, {
                "mediaId": media_id,
                "url": f"http://127.0.0.1:{PORT}/media/content/{key}",
                "method": "PUT",
                "headers": {"Content-Type": mime},
            })
            return

        if self.path.startswith("/media/") and self.path.endswith("/complete"):
            media_id = self.path[len("/media/"):-len("/complete")]
            body = self._json()
            with lock:
                state["completeCount"] += 1
                state["lastWidth"], state["lastHeight"] = body.get("width"), body.get("height")
                # 대소문자 무시. postgres의 uuid 컬럼이 둘 다 받으므로 실제 서버도 그렇다.
                item = media.get(media_id.lower())
                if item is None:
                    self._error(404, "NOT_FOUND", "미디어를 찾을 수 없습니다.")
                    return
                # 바이트가 오기 전에 complete하면 거절한다 — 순서가 뒤집혔는지 잡는다.
                if not item["uploaded"]:
                    self._error(400, "VALIDATION_FAILED", "업로드된 바이트가 없습니다.")
                    return
                item["status"] = "ready"
                item["width"], item["height"] = body.get("width"), body.get("height")
                self._send(200, {
                    "id": media_id.lower(), "kind": item["kind"],
                    "url": f"http://127.0.0.1:{PORT}/media/content/{item['key']}",
                    "width": item["width"], "height": item["height"],
                })
            return

        if self.path == "/auth/logout":
            self._body()
            self._send(200, {"ok": True})
            return

        self._error(404, "NOT_FOUND", "없음")


if __name__ == "__main__":
    print(f"미디어 스텁 :{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

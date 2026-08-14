#!/usr/bin/env python3
"""후속 수정 3건 검증용 스텁 서버.

기존 `Scripts/posts/poststub.py`로는 이 브랜치를 검증할 수 없다. 그쪽은 `/users/:id/posts`가
**id와 무관하게 같은 목록**을 돌려주므로(작성자가 항상 `ME`) "A 목록에 B 포스트가 섞였는가"를
물을 수 없고, 응답이 즉시 끝나 동시 요청의 경쟁 창이 생기지 않는다.

여기서 만드는 상황 셋:
  ① 사용자마다 **다른** 포스트를 돌려준다 — 교차 오염을 눈으로 셀 수 있다
  ② 응답을 `delay`만큼 늦춘다 — 두 요청이 실제로 겹친다(즉답이면 경쟁이 아예 안 생긴다)
  ③ 계정을 바꿔 끼운다(`account`) — 로그아웃 후 다른 계정 로그인을 흉내낸다

스레딩 서버여야 한다. 단일 스레드면 요청이 줄을 서서 ①②가 성립하지 않는다.
"""
import json, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8770

USER_A = "aaaaaaaa-0000-4000-8000-000000000001"
USER_B = "bbbbbbbb-0000-4000-8000-000000000002"

TEMPLATE = {
    "id": "11111111-0000-4000-8000-000000000001", "code": "grid4", "name": "네 컷",
    "cutCount": 4, "aspectRatio": "1:1",
    "slots": [{"x": 0, "y": 0, "width": 0.5, "height": 0.5},
              {"x": 0.5, "y": 0, "width": 0.5, "height": 0.5},
              {"x": 0, "y": 0.5, "width": 0.5, "height": 0.5},
              {"x": 0.5, "y": 0.5, "width": 0.5, "height": 0.5}],
}

state = {
    "delay": 0.25,          # 응답 지연(초). 경쟁 창을 넓힌다
    "account": USER_A,      # 지금 로그인한 계정. /feed가 이 계정의 것을 돌려준다
    "failBookmark": False,
    "failReaction": False,
    "failFollow": False,
    "failBlock": False,
    "userPostCount": 0,     # /users/:id/posts 요청 수 (id별)
    "feedCount": 0,
}
user_requests = {}          # user id -> 요청 수
lock = threading.Lock()


def post_for(owner, index):
    """소유자마다 **다른** id를 낸다 — 교차 오염이 id로 드러나야 한다."""
    return {
        "id": f"{owner[:8]}-1111-4000-8000-{index:012d}",
        "author": {"id": owner, "nickname": "A" if owner == USER_A else "B",
                   "avatarUrl": None},
        "template": TEMPLATE, "frame": None,
        "status": "published", "visibility": "friends",
        "caption": None, "thumbnailCutIndex": None, "cuts": [], "composed": None,
        "publishedAt": "2026-08-14T00:00:00.000Z",
        "createdAt": "2026-08-14T00:00:00.000Z",
        "commentCount": 0,
        "reactions": {"total": 0, "counts": [], "mine": None},
        "bookmarked": False,
    }


PAGE_SIZE = 2
TOTAL = 4


def page(owner, cursor):
    start = int(cursor) if cursor else 0
    items = [post_for(owner, i) for i in range(start, min(start + PAGE_SIZE, TOTAL))]
    nxt = start + PAGE_SIZE
    return {"items": items, "nextCursor": str(nxt) if nxt < TOTAL else None}


def profile(user_id, blocking=False):
    return {
        "id": user_id, "nickname": "A" if user_id == USER_A else "B", "avatarUrl": None,
        "friendCount": 0, "following": False, "followedBy": False,
        "friend": False, "blocking": blocking,
    }


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

    def _no_content(self):
        """204는 본문을 가질 수 없다. `_send(204, {})`로 두 바이트를 실으면 keep-alive가 깨진다."""
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _drain(self):
        """본문을 **반드시** 읽는다.

        읽지 않고 응답하면 keep-alive 연결에 바이트가 남아 다음 요청의 첫 줄에 섞인다.
        처음 돌렸을 때 `PUT /reaction`의 본문이 남아 바로 뒤 프로필 조회가
        `Unsupported method ('{"type":"like"}GET')` 501로 죽었다 — 앱이 아니라 여기 문제였다.
        """
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def _json(self):
        try:
            return json.loads(self._drain() or b"{}")
        except Exception:
            return {}

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/__state":
            with lock:
                self._send(200, {**state, "userRequests": dict(user_requests)})
            return

        cursor = (parse_qs(parsed.query).get("cursor") or [None])[0]

        if parsed.path == "/feed":
            with lock:
                state["feedCount"] += 1
                owner = state["account"]
                delay = state["delay"]
            time.sleep(delay)
            self._send(200, page(owner, cursor))
            return

        # 관계 목록. `/users/` 접두 분기보다 **먼저** 와야 한다 — 뒤에 두면 프로필 응답이
        # 돌아가고 UserPage 디코드가 실패해, 검사가 그 경로를 아예 밟지 않는다.
        # 실제로 처음에 그렇게 두어 ⑥의 SocialStore 검사가 통과만 하고 있었다.
        if parsed.path in ("/users/me/friends", "/users/me/followers", "/users/me/followees"):
            with lock:
                delay = state["delay"]
            time.sleep(delay)
            self._send(200, {"items": [{"id": USER_B, "nickname": "B", "avatarUrl": None}],
                             "nextCursor": None})
            return

        if parsed.path.startswith("/users/") and parsed.path.endswith("/posts"):
            owner = parsed.path[len("/users/"):-len("/posts")]
            with lock:
                user_requests[owner] = user_requests.get(owner, 0) + 1
                state["userPostCount"] += 1
                delay = state["delay"]
            # 지연은 락 **밖에서**. 안에서 자면 두 요청이 직렬화돼 경쟁이 사라진다.
            time.sleep(delay)
            self._send(200, page(owner, cursor))
            return

        if parsed.path.startswith("/users/"):
            self._send(200, profile(parsed.path[len("/users/"):]))
            return

        self._error(404, "NOT_FOUND", "없음")

    def do_POST(self):
        if self.path == "/__reset":
            patch = self._json()
            self._reset(patch)
            self._send(200, {"ok": True})
            return

        self._drain()
        if self.path.endswith("/follow"):
            with lock:
                fail = state["failFollow"]
            if fail:
                self._error(409, "ALREADY_FOLLOWING", "이미 팔로우 중입니다.")
            else:
                self._send(200, {"following": True, "friend": False})
            return

        if self.path.endswith("/block"):
            with lock:
                fail = state["failBlock"]
            if fail:
                self._error(409, "CANNOT_BLOCK_SELF", "자기 자신은 차단할 수 없습니다.")
            else:
                self._no_content()
            return

        self._error(404, "NOT_FOUND", "없음")

    def _reset(self, patch):
        with lock:
            state.update({
                "delay": 0.25, "account": USER_A,
                "failBookmark": False, "failReaction": False,
                "failFollow": False, "failBlock": False,
                "userPostCount": 0, "feedCount": 0,
            })
            state.update(patch)
            user_requests.clear()

    def do_PUT(self):
        self._drain()
        if self.path.endswith("/bookmark"):
            with lock:
                fail = state["failBookmark"]
            if fail:
                self._error(500, "INTERNAL_ERROR", "일시적인 오류입니다.")
            else:
                self._send(200, {"bookmarked": True})
            return

        if self.path.endswith("/reaction"):
            with lock:
                fail = state["failReaction"]
            if fail:
                self._error(500, "INTERNAL_ERROR", "일시적인 오류입니다.")
            else:
                self._send(200, {"total": 1, "counts": [{"type": "like", "count": 1}],
                                 "mine": "like"})
            return

        self._error(404, "NOT_FOUND", "없음")

    def do_DELETE(self):
        self._drain()
        self._error(404, "NOT_FOUND", "없음")


if __name__ == "__main__":
    print(f"후속 검증 스텁 :{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

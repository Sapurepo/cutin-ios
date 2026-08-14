#!/usr/bin/env python3
"""소셜·댓글·반응·신고 검증용 스텁 서버.

실제 서버의 **응답 모양 차이**를 그대로 흉내낸다. 여기가 이 스텁의 요점이다:

- `POST /users/:id/follow`   → 200 `FollowResult` (본문 있음)
- `DELETE /users/:id/follow` → **204, 본문 없음**
- `POST`/`DELETE /users/:id/block` → **204, 본문 없음**

셋을 같은 호출로 묶어 `FollowResult`로 디코드하면 언팔로우·차단이 항상 디코드 실패로 끝난다.
서버에서는 이미 처리된 뒤라 화면만 "안 된다"고 말한다 — 관대한 스텁으로는 안 잡힌다.

차단은 **양방향 팔로우와 친구 관계를 함께 끊는다**(컨트롤러 설명). 해제해도 복구하지 않는다.
"""
import json, sys, threading, uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8770
ME = "3f2c1b4a-5d6e-4f70-8a9b-0c1d2e3f4a5b"
PAGE_SIZE = 2

# id -> 닉네임. 검색·친구 목록이 여기서 나온다.
people = {}
following = set()      # 내가 팔로우하는 id
followers = set()      # 나를 팔로우하는 id
blocked = set()        # 내가 차단한 id
comments = {}          # postId -> [comment]
reactions = {}         # postId -> {userId: type}
reports = []

state = {
    "followCount": 0, "unfollowCount": 0, "blockCount": 0, "unblockCount": 0,
    "reactionPutCount": 0, "reactionDeleteCount": 0,
    "commentPostCount": 0, "commentDeleteCount": 0, "reportCount": 0,
    "lastSearchQuery": None, "lastReport": None,
    "seedPeople": 0, "seedComments": 0,
}
lock = threading.Lock()
POST_ID = "44444444-4444-4444-8444-444444444444"


def now(offset=0):
    return (datetime.now(timezone.utc) + timedelta(seconds=offset)).isoformat()


def summary(user_id):
    return {"id": user_id, "nickname": people.get(user_id), "avatarUrl": None}


def page(ids, cursor):
    ordered = sorted(ids)
    start = ordered.index(cursor) + 1 if cursor in ordered else 0
    window = ordered[start:start + PAGE_SIZE]
    tail = ordered[start + PAGE_SIZE:]
    return {"items": [summary(i) for i in window],
            "nextCursor": window[-1] if window and tail else None}


def reaction_summary(post_id):
    mine_map = reactions.get(post_id, {})
    counts = {}
    for value in mine_map.values():
        counts[value] = counts.get(value, 0) + 1
    return {
        "total": len(mine_map),
        "counts": [{"type": k, "count": v} for k, v in sorted(counts.items())],
        "mine": mine_map.get(ME),
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

    def _no_content(self):
        """204 — 본문이 아예 없다. 실제 서버가 팔로우 해제·차단에서 이 모양이다."""
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

    def _target(self, prefix, suffix):
        """경로에서 대상 id를 자른다. **쿼리를 뗀 뒤** 자른다 — `self.path`에는 `?cursor=…`가
        붙어 있어서 그대로 자르면 id에 커서가 섞인다(댓글 둘째 페이지가 빈 목록으로 왔다)."""
        path = urlparse(self.path).path
        return path[len(prefix):-len(suffix)].lower() if suffix else path[len(prefix):].lower()

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/__state":
            with lock:
                self._send(200, dict(state))
            return
        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return

        query = parse_qs(parsed.query)
        cursor = (query.get("cursor") or [None])[0]

        if parsed.path == "/users/me":
            self._send(200, {"id": ME, "nickname": "네컷러버", "avatarUrl": None,
                             "timezone": "Asia/Seoul", "onboardingCompleted": True})
            return

        with lock:
            if parsed.path == "/users/me/friends":
                self._send(200, page(list(following & followers), cursor))
                return
            if parsed.path == "/users/me/followers":
                self._send(200, page(list(followers), cursor))
                return
            if parsed.path == "/users/me/followees":
                self._send(200, page(list(following), cursor))
                return
            if parsed.path == "/users/search":
                term = (query.get("q") or [""])[0]
                state["lastSearchQuery"] = term
                hits = [i for i, name in people.items() if term.lower() in (name or "").lower()]
                self._send(200, page(hits, cursor))
                return
            if parsed.path == "/users/recommended":
                items = [dict(summary(i), mutualFriendCount=2)
                         for i in sorted(people) if i not in following][:3]
                self._send(200, {"items": items})
                return
            if parsed.path.endswith("/comments"):
                post_id = self._target("/posts/", "/comments")
                items = comments.get(post_id, [])
                start = 0
                if cursor:
                    ids = [c["id"] for c in items]
                    start = ids.index(cursor) + 1 if cursor in ids else 0
                window = items[start:start + PAGE_SIZE]
                tail = items[start + PAGE_SIZE:]
                self._send(200, {"items": window,
                                 "nextCursor": window[-1]["id"] if window and tail else None})
                return
            if parsed.path.startswith("/users/"):
                target = parsed.path[len("/users/"):].lower()
                if target not in people:
                    self._error(404, "USER_NOT_FOUND", "사용자를 찾을 수 없습니다.")
                    return
                self._send(200, {
                    "id": target, "nickname": people[target], "avatarUrl": None,
                    "friendCount": len(following & followers),
                    "following": target in following,
                    "followedBy": target in followers,
                    "friend": target in following and target in followers,
                    "blocking": target in blocked,
                })
                return

        self._error(404, "NOT_FOUND", "없음")

    def do_POST(self):
        if self.path == "/__reset":
            patch = self._json()
            with lock:
                people.clear(); following.clear(); followers.clear(); blocked.clear()
                comments.clear(); reactions.clear(); reports.clear()
                state.update({
                    "followCount": 0, "unfollowCount": 0, "blockCount": 0, "unblockCount": 0,
                    "reactionPutCount": 0, "reactionDeleteCount": 0,
                    "commentPostCount": 0, "commentDeleteCount": 0, "reportCount": 0,
                    "lastSearchQuery": None, "lastReport": None,
                    "seedPeople": 0, "seedComments": 0,
                })
                state.update(patch)
                for index in range(state["seedPeople"]):
                    person = f"1111{index:04d}-1111-4111-8111-111111111111"
                    people[person] = f"친구{index}"
                    if patch.get("seedFollowsMe"):
                        followers.add(person)
                for index in range(state["seedComments"]):
                    comments.setdefault(POST_ID, []).append({
                        "id": str(uuid.uuid4()),
                        "author": {"id": ME, "nickname": "네컷러버", "avatarUrl": None},
                        "body": f"댓글 {index}", "createdAt": now(index),
                    })
            self._send(200, {"ok": True})
            return

        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return

        if self.path.endswith("/follow"):
            target = self._target("/users/", "/follow")
            with lock:
                state["followCount"] += 1
                following.add(target)
                self._send(200, {"following": True,
                                 "friend": target in followers})
            return

        if self.path.endswith("/block"):
            target = self._target("/users/", "/block")
            with lock:
                state["blockCount"] += 1
                blocked.add(target)
                # 차단은 양방향 팔로우를 함께 끊는다.
                following.discard(target)
                followers.discard(target)
            self._no_content()
            return

        if self.path.endswith("/comments"):
            post_id = self._target("/posts/", "/comments")
            body = self._json()
            with lock:
                state["commentPostCount"] += 1
                if not (body.get("body") or "").strip():
                    self._error(400, "VALIDATION_FAILED", "내용을 입력해주세요.")
                    return
                comment = {
                    "id": str(uuid.uuid4()),
                    "author": {"id": ME, "nickname": "네컷러버", "avatarUrl": None},
                    "body": body["body"], "createdAt": now(100),
                }
                comments.setdefault(post_id, []).append(comment)
            self._send(201, comment)
            return

        if self.path == "/reports":
            body = self._json()
            with lock:
                state["reportCount"] += 1
                state["lastReport"] = body
                report = {"id": str(uuid.uuid4()),
                          "targetType": body.get("targetType"),
                          "targetId": body.get("targetId"),
                          "reason": body.get("reason"),
                          "status": "pending", "createdAt": now()}
                reports.append(report)
            self._send(201, report)
            return

        if self.path == "/auth/logout":
            self._raw()
            self._send(200, {"ok": True})
            return

        self._error(404, "NOT_FOUND", "없음")

    def do_PUT(self):
        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return
        if self.path.endswith("/reaction"):
            post_id = self._target("/posts/", "/reaction")
            body = self._json()
            with lock:
                state["reactionPutCount"] += 1
                reactions.setdefault(post_id, {})[ME] = body.get("type")
                self._send(200, reaction_summary(post_id))
            return
        self._error(404, "NOT_FOUND", "없음")

    def do_DELETE(self):
        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return

        if self.path.endswith("/follow"):
            target = self._target("/users/", "/follow")
            with lock:
                state["unfollowCount"] += 1
                following.discard(target)
            self._no_content()   # 본문 없음
            return

        if self.path.endswith("/block"):
            target = self._target("/users/", "/block")
            with lock:
                state["unblockCount"] += 1
                blocked.discard(target)
            self._no_content()   # 본문 없음. 끊긴 팔로우는 복구하지 않는다
            return

        if self.path.endswith("/reaction"):
            post_id = self._target("/posts/", "/reaction")
            with lock:
                state["reactionDeleteCount"] += 1
                reactions.get(post_id, {}).pop(ME, None)
                self._send(200, reaction_summary(post_id))
            return

        if "/comments/" in self.path:
            post_id, comment_id = self.path[len("/posts/"):].split("/comments/")
            with lock:
                state["commentDeleteCount"] += 1
                items = comments.get(post_id.lower(), [])
                comments[post_id.lower()] = [c for c in items
                                             if c["id"] != comment_id.lower()]
            self._no_content()
            return

        self._error(404, "NOT_FOUND", "없음")


if __name__ == "__main__":
    print(f"소셜 스텁 :{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

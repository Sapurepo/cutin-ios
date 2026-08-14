#!/usr/bin/env python3
"""포스트 생애주기·피드 검증용 스텁 서버.

발행은 왕복이 컷 4장 기준 **열여섯 번**이고, 서버가 각 단계에서 거절 조건을 갖는다.
그 조건을 그대로 흉내낸다 — 관대한 스텁으로는 순서를 시험할 수 없다.

- `POST /posts`는 계정당 draft 하나만 만든다 (`DRAFT_ALREADY_EXISTS`, 409)
- `PATCH /posts/:id`의 `cuts`는 **ready이고 kind가 cut인 내 미디어**만 받는다
- `POST /posts/:id/publish`는 컷이 템플릿 수만큼 차 있어야 하고, 합성본이 ready여야 한다
- `GET /feed`·`/users/me/bookmarks`·`/users/:id/posts`는 커서 페이지를 돌려준다
"""
import json, sys, threading, uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8769
ME = "3f2c1b4a-5d6e-4f70-8a9b-0c1d2e3f4a5b"
PAGE_SIZE = 2   # 작게 둬야 커서 페이징이 실제로 여러 번 돈다

TEMPLATE = {
    "id": "11111111-1111-4111-8111-111111111111",
    "code": "grid4", "name": "네 컷", "cutCount": 4, "aspectRatio": "1:1",
    "slots": [{"x": x, "y": y, "width": 0.5, "height": 0.5}
              for y in (0, 0.5) for x in (0, 0.5)],
}
FRAME = {
    "id": "22222222-2222-4222-8222-222222222222",
    "code": "basic", "name": "베이직", "background": "#1E1E21", "foreground": "#F5F5F4",
    "padding": 0.0111, "gutter": 0.0111, "cellRadius": 0.0083, "footer": None,
}

state = {
    "createCount": 0, "getDraftCount": 0, "patchCount": 0, "publishCount": 0,
    "deleteCount": 0, "bookmarkPutCount": 0, "bookmarkDeleteCount": 0,
    "lastCuts": None, "lastVisibility": None, "lastCaption": None, "lastFrameId": None,
    "lastPublishBody": None,
    "seedPublished": 0,   # 피드에 미리 깔아 둘 발행본 수
    "seedDraft": False,   # 발행이 끊겨 남은 draft를 미리 심는다
}
media = {}    # id -> {kind, status}
posts = {}    # id -> post dict
bookmarks = set()
lock = threading.Lock()


def now(offset=0):
    return (datetime.now(timezone.utc) + timedelta(seconds=offset)).isoformat()


def new_post(status="draft", index=0):
    post_id = str(uuid.uuid4())
    posts[post_id] = {
        "id": post_id,
        "author": {"id": ME, "nickname": "네컷러버", "avatarUrl": None},
        "template": TEMPLATE, "frame": None,
        "status": status, "visibility": "friends",
        "caption": None, "thumbnailCutIndex": None, "cuts": [],
        "composed": None, "publishedAt": now(-index) if status == "published" else None,
        "createdAt": now(-index),
        "commentCount": 0,
        "reactions": {"total": 0, "counts": [], "mine": None},
        "bookmarked": False,
    }
    return posts[post_id]


def view(post):
    item = dict(post)
    item["bookmarked"] = post["id"] in bookmarks
    return item


def page(items, cursor):
    """커서 = 마지막 항목의 id. 서버는 시각+id를 인코딩하지만 순서만 지키면 검증에 충분하다."""
    ordered = sorted(items, key=lambda p: p["createdAt"], reverse=True)
    start = 0
    if cursor:
        ids = [p["id"] for p in ordered]
        start = ids.index(cursor) + 1 if cursor in ids else 0
    window = ordered[start:start + PAGE_SIZE]
    tail = ordered[start + PAGE_SIZE:]
    return {
        "items": [view(p) for p in window],
        "nextCursor": window[-1]["id"] if window and tail else None,
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

    # MARK: GET

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/__state":
            with lock:
                self._send(200, dict(state))
            return
        if parsed.path.startswith("/media/content/"):
            self._send(200, {"ok": True})
            return

        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return

        cursor = (parse_qs(parsed.query).get("cursor") or [None])[0]

        if parsed.path == "/users/me":
            self._send(200, {"id": ME, "nickname": "네컷러버", "avatarUrl": None,
                             "timezone": "Asia/Seoul", "onboardingCompleted": True})
            return
        if parsed.path == "/templates":
            self._send(200, {"items": [TEMPLATE]})
            return
        if parsed.path == "/frames":
            self._send(200, {"items": [FRAME]})
            return

        with lock:
            if parsed.path == "/feed":
                published = [p for p in posts.values() if p["status"] == "published"]
                self._send(200, page(published, cursor))
                return
            if parsed.path == "/users/me/bookmarks":
                marked = [p for p in posts.values() if p["id"] in bookmarks]
                self._send(200, page(marked, cursor))
                return
            if parsed.path == "/posts/draft":
                state["getDraftCount"] += 1
                draft = next((p for p in posts.values() if p["status"] == "draft"), None)
                if draft is None:
                    self._error(404, "DRAFT_NOT_FOUND", "작성 중인 포스트가 없습니다.")
                else:
                    self._send(200, view(draft))
                return
            if parsed.path.endswith("/posts") and parsed.path.startswith("/users/"):
                mine = [p for p in posts.values()
                        if p["status"] == "published" and p["author"]["id"] == ME]
                self._send(200, page(mine, cursor))
                return
            if parsed.path.endswith("/share"):
                post_id = parsed.path[len("/posts/"):-len("/share")].lower()
                post = posts.get(post_id)
                if post is None or post["status"] != "published":
                    self._error(404, "POST_NOT_FOUND", "포스트를 찾을 수 없습니다.")
                elif post["visibility"] == "private":
                    self._error(403, "POST_NOT_SHAREABLE", "비공개 포스트는 공유할 수 없습니다.")
                else:
                    self._send(200, {"url": f"http://127.0.0.1:{PORT}/p/{post_id}"})
                return
            if parsed.path.startswith("/posts/"):
                post = posts.get(parsed.path[len("/posts/"):].lower())
                if post is None:
                    self._error(404, "POST_NOT_FOUND", "포스트를 찾을 수 없습니다.")
                else:
                    self._send(200, view(post))
                return

        self._error(404, "NOT_FOUND", "없음")

    # MARK: PUT · DELETE · PATCH

    def do_PUT(self):
        if self.path.startswith("/media/content/"):
            self._raw()
            with lock:
                for item in media.values():
                    if item["key"] == self.path[len("/media/content/"):]:
                        item["uploaded"] = True
            self._send(200, {"ok": True})
            return
        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return
        if self.path.endswith("/bookmark"):
            post_id = self.path[len("/posts/"):-len("/bookmark")].lower()
            with lock:
                state["bookmarkPutCount"] += 1
                bookmarks.add(post_id)
            self._send(200, {"bookmarked": True})
            return
        self._error(404, "NOT_FOUND", "없음")

    def do_DELETE(self):
        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return
        if self.path.endswith("/bookmark"):
            post_id = self.path[len("/posts/"):-len("/bookmark")].lower()
            with lock:
                state["bookmarkDeleteCount"] += 1
                bookmarks.discard(post_id)
            self._send(200, {"bookmarked": False})
            return
        if self.path.startswith("/posts/"):
            post_id = self.path[len("/posts/"):].lower()
            with lock:
                state["deleteCount"] += 1
                if post_id not in posts:
                    self._error(404, "POST_NOT_FOUND", "포스트를 찾을 수 없습니다.")
                    return
                del posts[post_id]
            self._send(200, {"ok": True})
            return
        self._error(404, "NOT_FOUND", "없음")

    def do_PATCH(self):
        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return
        if not self.path.startswith("/posts/"):
            self._error(404, "NOT_FOUND", "없음")
            return

        body = self._json()
        post_id = self.path[len("/posts/"):].lower()
        with lock:
            state["patchCount"] += 1
            post = posts.get(post_id)
            if post is None or post["status"] != "draft":
                self._error(404, "POST_NOT_FOUND", "포스트를 찾을 수 없습니다.")
                return

            if "cuts" in body:
                cuts = body["cuts"]
                indexes = [c["cutIndex"] for c in cuts]
                if len(set(indexes)) != len(indexes):
                    self._error(400, "DUPLICATE_CUT_INDEX", "같은 자리에 두 컷을 넣을 수 없습니다.")
                    return
                if any(i >= TEMPLATE["cutCount"] for i in indexes):
                    self._error(400, "CUT_INDEX_OUT_OF_RANGE", "템플릿의 컷 수를 넘는 자리입니다.")
                    return
                # ready이고 kind가 cut인 미디어만 받는다 — 업로드 순서를 시험하는 조건이다.
                for cut in cuts:
                    item = media.get(str(cut["mediaId"]).lower())
                    if item is None or item["status"] != "ready" or item["kind"] != "cut":
                        self._error(400, "MEDIA_NOT_READY", "컷 업로드가 끝나지 않았습니다.")
                        return
                post["cuts"] = [
                    {"cutIndex": c["cutIndex"],
                     "media": {"id": c["mediaId"], "kind": "cut",
                               "url": f"http://127.0.0.1:{PORT}/media/content/cut/{c['mediaId']}.jpg",
                               "width": 100, "height": 100}}
                    for c in sorted(cuts, key=lambda c: c["cutIndex"])
                ]
                state["lastCuts"] = indexes

            if "caption" in body:
                post["caption"] = body["caption"]
                state["lastCaption"] = body["caption"]
            if "frameId" in body:
                post["frame"] = None if body["frameId"] is None else FRAME
                state["lastFrameId"] = body["frameId"]
            if "visibility" in body:
                post["visibility"] = body["visibility"]
            if "thumbnailCutIndex" in body:
                post["thumbnailCutIndex"] = body["thumbnailCutIndex"]

            self._send(200, view(post))

    # MARK: POST

    def do_POST(self):
        if self.path == "/__reset":
            patch = self._json()
            with lock:
                posts.clear(); media.clear(); bookmarks.clear()
                state.update({
                    "createCount": 0, "getDraftCount": 0, "patchCount": 0, "publishCount": 0,
                    "deleteCount": 0, "bookmarkPutCount": 0, "bookmarkDeleteCount": 0,
                    "lastCuts": None, "lastVisibility": None, "lastCaption": None,
                    "lastFrameId": None, "lastPublishBody": None, "seedPublished": 0,
                    "seedDraft": False,
                })
                state.update(patch)
                # POST /posts를 거치지 않고 심는다 — 하니스의 셋업이 카운터를 올리면
                # "앱이 몇 번 만들려 했는가"를 셀 수 없다.
                if state["seedDraft"]:
                    new_post("draft")
                for index in range(state["seedPublished"]):
                    seeded = new_post("published", index)
                    seeded["composed"] = {
                        "id": str(uuid.uuid4()), "kind": "composed",
                        "url": f"http://127.0.0.1:{PORT}/media/content/composed/{index}.jpg",
                        "width": 1080, "height": 1080,
                    }
            self._send(200, {"ok": True})
            return

        if self.path == "/auth/refresh":
            self._raw()
            self._send(200, {"accessToken": "GOOD", "refreshToken": "R2", "expiresIn": 3600})
            return

        if not self._authorized():
            self._error(401, "UNAUTHORIZED", "인증이 필요합니다.")
            return

        if self.path == "/media/uploads":
            body = self._json()
            media_id = str(uuid.uuid4())
            key = f"{body.get('kind')}/{media_id}.jpg"
            with lock:
                media[media_id] = {"kind": body.get("kind"), "status": "pending",
                                   "key": key, "uploaded": False}
            self._send(201, {"mediaId": media_id,
                             "url": f"http://127.0.0.1:{PORT}/media/content/{key}",
                             "method": "PUT",
                             "headers": {"Content-Type": body.get("mime")}})
            return

        if self.path.startswith("/media/") and self.path.endswith("/complete"):
            media_id = self.path[len("/media/"):-len("/complete")].lower()
            body = self._json()
            with lock:
                item = media.get(media_id)
                if item is None:
                    self._error(404, "NOT_FOUND", "미디어를 찾을 수 없습니다.")
                    return
                if not item["uploaded"]:
                    self._error(400, "VALIDATION_FAILED", "업로드된 바이트가 없습니다.")
                    return
                item["status"] = "ready"
                self._send(200, {"id": media_id, "kind": item["kind"],
                                 "url": f"http://127.0.0.1:{PORT}/media/content/{item['key']}",
                                 "width": body.get("width"), "height": body.get("height")})
            return

        if self.path == "/posts":
            self._json()
            with lock:
                state["createCount"] += 1
                # 계정당 draft 하나. 실제 서버가 유니크 제약으로 막는다.
                if any(p["status"] == "draft" for p in posts.values()):
                    self._error(409, "DRAFT_ALREADY_EXISTS",
                                "이전 포스트 완료 후 생성할 수 있어요.")
                    return
                self._send(201, view(new_post("draft")))
            return

        if self.path.endswith("/publish"):
            post_id = self.path[len("/posts/"):-len("/publish")].lower()
            body = self._json()
            with lock:
                state["publishCount"] += 1
                state["lastPublishBody"] = body
                state["lastVisibility"] = body.get("visibility")
                post = posts.get(post_id)
                if post is None or post["status"] != "draft":
                    self._error(404, "POST_NOT_FOUND", "포스트를 찾을 수 없습니다.")
                    return
                if len(post["cuts"]) != TEMPLATE["cutCount"]:
                    self._error(400, "CUTS_INCOMPLETE",
                                f"컷 {TEMPLATE['cutCount']}장을 모두 채워야 발행할 수 있습니다.")
                    return
                composed = media.get(str(body.get("composedMediaId")).lower())
                if composed is None or composed["status"] != "ready" \
                        or composed["kind"] != "composed":
                    self._error(400, "MEDIA_NOT_READY", "합성본 업로드가 끝나지 않았습니다.")
                    return
                post["status"] = "published"
                post["publishedAt"] = now()
                post["composed"] = {
                    "id": body["composedMediaId"], "kind": "composed",
                    "url": f"http://127.0.0.1:{PORT}/media/content/{composed['key']}",
                    "width": 1080, "height": 1080,
                }
                if body.get("visibility"):
                    post["visibility"] = body["visibility"]
                post["thumbnailCutIndex"] = body.get("thumbnailCutIndex") \
                    or post["thumbnailCutIndex"] or 0
                self._send(200, view(post))
            return

        if self.path == "/auth/logout":
            self._raw()
            self._send(200, {"ok": True})
            return

        self._error(404, "NOT_FOUND", "없음")


if __name__ == "__main__":
    print(f"포스트 스텁 :{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

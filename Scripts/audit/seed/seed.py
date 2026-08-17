#!/usr/bin/env python3
"""UI 감사용 시드 — 로컬 서버에 사용자 5명·포스트 15개·팔로우·댓글·반응을 **API로** 넣는다.

카카오 로그인 없이 서버 `.env`의 JWT_SECRET으로 액세스 토큰을 직접 서명한다(`shared/auth/tokens.ts`와
같은 형식). '나'(ME)는 기존 사용자다 — 시뮬레이터에서 그 계정으로 화면을 본다.

    CUTIN_BACKEND=~/orca/workspaces/cutin-backend/dev  CUTIN_ME=<내 user id>  python3 seed.py

멱등이다 — 다시 돌리면 없는 것만 만든다. 사진은 시뮬레이터 샘플 사진(DCIM)과 macOS 배경화면을 쓴다.
"""
import base64, hashlib, hmac, json, os, subprocess, sys, time, uuid, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
API = os.environ.get("CUTIN_API", "http://localhost:3000")
BACKEND = os.path.expanduser(os.environ.get("CUTIN_BACKEND", "~/orca/workspaces/cutin-backend/dev"))
SECRET = [l.split("=", 1)[1].strip() for l in open(f"{BACKEND}/.env") if l.startswith("JWT_SECRET=")][0]
ME = os.environ.get("CUTIN_ME") or sys.exit("CUTIN_ME(내 user id)가 필요합니다 — psql: select id, nickname from users")
DEV = os.environ.get("CUTIN_SIM", "F4A70383-9134-477E-BCCA-B7824317EDE0")


def psql(sql):
    out = subprocess.run(["docker", "exec", "cutin-postgres-1", "psql", "-U", "cutin", "-d", "cutin", "-tAc", sql],
                         capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stderr)
    return out.stdout.strip()


def b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def jwt(user_id, hours=12):
    h = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    now = int(time.time())
    p = b64(json.dumps({"sub": user_id, "iss": "cutin", "iat": now, "exp": now + hours * 3600}).encode())
    sig = b64(hmac.new(SECRET.encode(), f"{h}.{p}".encode(), hashlib.sha256).digest())
    return f"{h}.{p}.{sig}"


def call(method, path, token, body=None, raw=None, headers=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if raw is None and body is not None:
        req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req) as r:
            txt = r.read()
            return json.loads(txt) if txt else None
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {path} -> {e.code} {e.read().decode()[:300]}")


def upload(token, path, kind, w, h):
    target = call("POST", "/media/uploads", token, {"kind": kind, "mime": "image/jpeg"})
    url = target["url"] if target["url"].startswith("http") else API + target["url"]
    req = urllib.request.Request(url, data=open(path, "rb").read(), method=target.get("method", "PUT"))
    req.add_header("Authorization", f"Bearer {token}")
    for k, v in (target.get("headers") or {}).items():
        req.add_header(k, v)
    urllib.request.urlopen(req).read()
    return call("POST", f"/media/{target['mediaId']}/complete", token, {"width": w, "height": h})["id"]


def size(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], capture_output=True, text=True).stdout
    vals = [int(l.split(":")[1]) for l in out.splitlines() if "pixel" in l]
    return vals[0], vals[1]


# ---------- 카탈로그 ----------
templates = {r.split("|")[0]: r.split("|")[1:] for r in psql(
    "select code, id, aspect_ratio, slots from templates").splitlines()}
frames = {r.split("|")[0]: r.split("|")[1:] for r in psql(
    "select code, id, background, foreground, padding, gutter, cell_radius, coalesce(footer,'') from frames").splitlines()}

# 시드 사용자
USERS = [
    ("하늘바다", "IMG_0006.jpg"),
    ("민지", "IMG_0004.JPG"),
    ("준호_필름", "IMG_0002.JPG"),
    ("소율", "IMG_0005.JPG"),
    ("도윤", "sonoma.jpg"),
]

# (id, owner, template, frame, sources, offsets, caption, visibility, thumbnailCutIndex)
POSTS = [
    ("m1", "me", "grid4", "white", ["IMG_0001.JPG", "IMG_0002.JPG", "IMG_0003.JPG", "IMG_0005.JPG"], [0.2, 0.5, 0.8, 0.4], "여름 끝자락, 넷이서", "friends", 2),
    ("m2", "me", "strip4", "peach", ["IMG_0004.JPG", "IMG_0006.jpg", "IMG_0004.JPG", "IMG_0006.jpg"], [0.3, 0.6, 0.7, 0.2], None, "friends", None),
    ("m3", "me", "grid6", "basic", ["sonoma.jpg", "horizon.jpg", "IMG_0001.JPG", "IMG_0003.JPG", "IMG_0005.JPG", "IMG_0002.JPG"], [0.5, 0.5, 0.3, 0.7, 0.5, 0.6], "주말 산책 기록. 여섯 장은 처음 써 봤는데 생각보다 괜찮다", "public", None),
    ("p1", "하늘바다", "grid4", "white", ["IMG_0006.jpg", "IMG_0006.jpg", "IMG_0006.jpg", "IMG_0006.jpg"], [0.1, 0.4, 0.7, 0.95], "바다 보러 왔다 🌊", "public", None),
    ("p2", "민지", "strip4", "noir", ["IMG_0004.JPG", "IMG_0004.JPG", "IMG_0004.JPG", "IMG_0004.JPG"], [0.1, 0.35, 0.65, 0.9], "오늘의 꽃", "friends", 1),
    ("p3", "준호_필름", "bigLeft", "peach", ["IMG_0002.JPG", "IMG_0001.JPG", "IMG_0003.JPG", "IMG_0005.JPG"], [0.5, 0.2, 0.6, 0.8], "필름 느낌 프레임 테스트. 왼쪽 큰 컷이 마음에 든다", "public", 0),
    ("p4", "소율", "grid6", "mint", ["IMG_0005.JPG", "IMG_0003.JPG", "IMG_0005.JPG", "IMG_0003.JPG", "IMG_0005.JPG", "IMG_0003.JPG"], [0.1, 0.9, 0.3, 0.7, 0.5, 0.5], None, "friends", None),
    ("p5", "도윤", "pair2", "basic", ["sonoma.jpg", "horizon.jpg"], [0.5, 0.5], "산 위에서", "public", None),
    ("p6", "하늘바다", "single", "butter", ["IMG_0001.JPG"], [0.5], "한 장으로도 충분한 날", "friends", None),
    ("p7", "민지", "strip4wide", "lavender", ["IMG_0003.JPG", "IMG_0002.JPG", "IMG_0001.JPG", "IMG_0005.JPG"], [0.2, 0.4, 0.6, 0.8], "가로 스트립은 피드에서 어떻게 보이려나", "public", None),
    ("p8", "준호_필름", "grid4", "cherry", ["IMG_0002.JPG", "IMG_0002.JPG", "IMG_0002.JPG", "IMG_0002.JPG"], [0.0, 0.33, 0.66, 1.0], "체리 프레임 🍒", "friends", None),
    ("p9", "소율", "strip4", "white", ["horizon.jpg", "sonoma.jpg", "horizon.jpg", "sonoma.jpg"], [0.2, 0.8, 0.5, 0.3], "노을", "public", None),
    ("p10", "도윤", "grid4", "basic", ["IMG_0005.JPG", "IMG_0006.jpg", "IMG_0004.JPG", "IMG_0001.JPG"], [0.5, 0.5, 0.5, 0.5], "친구들이랑 오랜만에. 캡션이 길어지면 카드에서 어떻게 잘리는지도 봐야 해서 일부러 길게 써 본다. 두 줄 세 줄 넘어가면 더보기가 필요할까?", "friends", None),
    ("p11", "하늘바다", "bigLeft", "noir", ["IMG_0006.jpg", "IMG_0001.JPG", "IMG_0002.JPG", "IMG_0003.JPG"], [0.5, 0.5, 0.5, 0.5], None, "public", None),
    ("p12", "민지", "single", "white", ["IMG_0004.JPG"], [0.5], "🌷", "friends", None),
]

COMMENTS = {  # post id -> [(author, body)]
    "m1": [("하늘바다", "넷이서라니 부럽다"), ("민지", "두 번째 컷 표정 뭐야 ㅋㅋㅋ"), ("소율", "다음엔 나도 껴줘")],
    "m3": [("도윤", "여섯 컷 좋은데?")],
    "p1": [("me", "어디 바다야?"), ("하늘바다", "@토키유키 강릉!"), ("민지", "가고 싶다")],
    "p3": [("me", "왼쪽 큰 컷 구도 좋다"), ("소율", "필름 느낌 진짜 나네")],
    "p10": [("me", "긴 캡션 테스트 잘 보임")],
}
REACTIONS = {  # post id -> [(user, type)]
    "m1": [("하늘바다", "love"), ("민지", "haha"), ("준호_필름", "like"), ("소율", "wow")],
    "m2": [("도윤", "like")],
    "m3": [("하늘바다", "like"), ("소율", "love")],
    "p1": [("me", "love"), ("민지", "like")],
    "p3": [("me", "wow")],
    "p5": [("me", "like")],
    "p9": [("me", "love"), ("하늘바다", "love")],
}
FOLLOWS = [  # follower -> followee
    ("me", "하늘바다"), ("me", "민지"), ("me", "준호_필름"), ("me", "소율"), ("me", "도윤"),
    ("하늘바다", "me"), ("민지", "me"), ("준호_필름", "me"), ("도윤", "me"), ("소율", "me"),
    ("하늘바다", "민지"), ("민지", "하늘바다"), ("소율", "민지"), ("도윤", "소율"),
]

# ---------- 0) 원본 사진 ----------
os.makedirs(f"{HERE}/src", exist_ok=True)
if not os.path.exists(f"{HERE}/src/sonoma.jpg"):
    dcim = os.path.expanduser(f"~/Library/Developer/CoreSimulator/Devices/{DEV}/data/Media/DCIM/100APPLE")
    for n in ["IMG_0001.JPG", "IMG_0002.JPG", "IMG_0003.JPG", "IMG_0004.JPG", "IMG_0005.JPG"]:
        subprocess.run(["cp", f"{dcim}/{n}", f"{HERE}/src/{n}"], check=True)
    subprocess.run(["sips", "-s", "format", "jpeg", "-Z", "2000", f"{dcim}/IMG_0006.HEIC", "--out", f"{HERE}/src/IMG_0006.jpg"], capture_output=True, check=True)
    subprocess.run(["sips", "-s", "format", "jpeg", "-Z", "2000", "/System/Library/Desktop Pictures/Sonoma.heic", "--out", f"{HERE}/src/sonoma.jpg"], capture_output=True, check=True)
    subprocess.run(["sips", "-s", "format", "jpeg", "-Z", "2000", "/System/Library/Desktop Pictures/.wallpapers/Sonoma Horizon/Sonoma Horizon.heic", "--out", f"{HERE}/src/horizon.jpg"], capture_output=True, check=True)

# ---------- 1) 이미지 ----------
specs = []
for pid, owner, tcode, fcode, srcs, offs, *_ in POSTS:
    tid, aspect, slots = templates[tcode]
    fid, bg, fg, pad, gut, rad, footer = frames[fcode]
    specs.append({"id": pid, "template": tcode, "aspect": aspect, "slots": json.loads(slots),
                  "padding": float(pad), "gutter": float(gut), "radius": float(rad), "bg": bg, "fg": fg,
                  "footer": footer == "logoDate", "sources": srcs, "offsets": offs})
# 아바타용 스펙 — single/basic으로 정사각 하나
for nick, src in USERS:
    tid, aspect, slots = templates["single"]
    specs.append({"id": f"avatar-{nick}", "template": "single", "aspect": "1:1", "slots": [{"x": 0, "y": 0, "width": 1, "height": 1}],
                  "padding": 0, "gutter": 0, "radius": 0, "bg": "#000000", "fg": "#FFFFFF", "footer": False, "sources": [src], "offsets": [0.5]})
open(f"{HERE}/spec.json", "w").write(json.dumps(specs))
out = f"{HERE}/out"
if not os.path.exists(f"{out}/p12/composed.jpg"):
    subprocess.run(["swift", f"{HERE}/compose.swift", f"{HERE}/spec.json", f"{HERE}/src", out], check=True)

# ---------- 2) 사용자 ----------
ids = {"me": ME}
for nick, _ in USERS:
    existing = psql(f"select id from users where nickname='{nick}'")
    if existing:
        ids[nick] = existing
        continue
    uid = str(uuid.uuid4())
    psql(f"insert into users (id, nickname, timezone, onboarding_completed_at) values ('{uid}','{nick}','Asia/Seoul', now())")
    ids[nick] = uid
tokens = {k: jwt(v) for k, v in ids.items()}
print("users:", ids)

for nick, _ in USERS:
    me = call("GET", "/users/me", tokens[nick])
    if not me.get("avatarUrl"):
        p = f"{out}/avatar-{nick}/cut0.jpg"
        mid = upload(tokens[nick], p, "avatar", *size(p))
        call("PATCH", "/users/me", tokens[nick], {"avatarMediaId": mid})
        print("avatar", nick)

# ---------- 3) 포스트 ----------
post_ids = {}
for pid, owner, tcode, fcode, srcs, offs, caption, vis, thumb in POSTS:
    tok = tokens[owner]
    tid = templates[tcode][0]
    fid = frames[fcode][0]
    # 이미 있는지 — 캡션 대신 시드 마커를 comments? 단순히 카운트로 판단: 소유자의 published 포스트 중 같은 템플릿·프레임·캡션
    existing = psql(f"select id from posts where author_id='{ids[owner]}' and template_id='{tid}' and coalesce(caption,'')='{(caption or '').replace(chr(39), chr(39)*2)}' and published_at is not null limit 1")
    if existing:
        post_ids[pid] = existing
        continue
    try:
        draft = call("GET", "/posts/draft", tok)
    except SystemExit as e:
        if "404" not in str(e): raise
        draft = call("POST", "/posts", tok, {"templateId": tid})
    cuts = []
    for i in range(len(srcs)):
        p = f"{out}/{pid}/cut{i}.jpg"
        cuts.append({"cutIndex": i, "mediaId": upload(tok, p, "cut", *size(p))})
    body = {"templateId": tid, "frameId": fid, "caption": caption, "cuts": cuts}
    if thumb is not None:
        body["thumbnailCutIndex"] = thumb
    call("PATCH", f"/posts/{draft['id']}", tok, body)
    p = f"{out}/{pid}/composed.jpg"
    comp = upload(tok, p, "composed", *size(p))
    post = call("POST", f"/posts/{draft['id']}/publish", tok, {"composedMediaId": comp, "visibility": vis})
    post_ids[pid] = post["id"]
    print("post", pid, post["id"])
    time.sleep(0.3)  # publishedAt 순서가 목록 순서다

# ---------- 4) 팔로우 ----------
for a, b in FOLLOWS:
    try:
        call("POST", f"/users/{ids[b]}/follow", tokens[a])
    except SystemExit as e:
        if "409" not in str(e): raise
print("follows ok")

# ---------- 5) 댓글·반응 ----------
for pid, items in COMMENTS.items():
    for author, body in items:
        if psql(f"select 1 from comments where post_id='{post_ids[pid]}' and body='{body}' and deleted_at is null limit 1"):
            continue
        call("POST", f"/posts/{post_ids[pid]}/comments", tokens[author], {"body": body})
for pid, items in REACTIONS.items():
    for user, kind in items:
        call("PUT", f"/posts/{post_ids[pid]}/reaction", tokens[user], {"type": kind})
print("comments/reactions ok")

# 나의 액세스 토큰(시뮬레이터 주입용)
open(f"{HERE}/me.token", "w").write(tokens["me"])
print("me token ->", f"{HERE}/me.token")

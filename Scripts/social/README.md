# 소셜 · 댓글 · 반응 · 신고 검증

친구 관계(`SocialStore`), 댓글(`CommentStore`), 반응·신고를 확인하는 도구입니다.
**이 폴더는 앱 타깃에 들어가지 않습니다.**

## 왜 검사하는가 — 응답 모양이 오퍼레이션마다 다르다

```
POST   /users/:id/follow  → 200 FollowResult  (본문 있음)
DELETE /users/:id/follow  → 204, 본문 없음
POST   /users/:id/block   → 204, 본문 없음
DELETE /users/:id/block   → 204, 본문 없음
```

셋을 같은 호출로 묶어 `FollowResult`로 디코드하면 **언팔로우·차단이 항상 디코드 실패로**
끝납니다. 서버에서는 이미 처리된 뒤라 사용자는 "언팔로우가 안 된다"고 보고, 다시 눌러도 같은
일이 반복됩니다. 코드만 보면 대칭이라 눈으로는 잡히지 않습니다.

## 차단은 연쇄 효과가 있다

차단 즉시 서버가 **양방향 팔로우와 친구 관계를 함께 끊고**, 해제해도 복구하지 않습니다
(컨트롤러 설명). 앱이 `blocking`만 손으로 켜면 나머지 세 값이 어긋납니다 — 프로필을 다시
받아야만 맞습니다.

## 검사 항목

| | 시나리오 | 보는 것 |
|---|---|---|
| ① | 팔로우 | 서버가 준 `FollowResult` 사용 · **맞팔이면 그 자리에서 친구** |
| ② | **언팔로우** | 204에서도 상태가 풀리는지 |
| ③ | **차단** | 팔로우가 함께 끊기는지 · 해제해도 복구되지 않는지 |
| ④ | 검색·목록 | 커서 페이징 · 중복 없음 · **새 질의는 결과를 갈아끼움** · 팔로우가 친구 목록을 무효화 |
| ⑤ | 댓글 | 페이징 · 앞뒤 공백 다듬기 · **맨 뒤에 붙기** · 빈 댓글은 왕복 안 함 · 삭제 |
| ⑥ | 반응 | 요약 전체 사용 · **교체는 PUT 하나** · 같은 반응은 취소 |
| ⑦ | 신고 | 대상·사유 전달 · **빈 상세는 키를 뺌** |

⑦의 마지막이 중요한 이유: 빈 문자열을 실으면 서버가 "내용 없음"이 아니라 "빈 내용"으로
저장합니다. 어드민이 신고를 읽을 때 그 차이가 드러납니다.

## 절차

```bash
python3 Scripts/social/socialstub.py 8770 &
cp Scripts/social/SocialHarness.swift Cutin/Friends/

# CutinApp의 init()에 한 줄 (커밋하지 않는다)
#   #if DEBUG
#   if SocialHarness.isRequested { Task { await SocialHarness.run() } }
#   #endif

DEV=$(xcrun simctl list devices available | grep -A9 "iOS 26" | grep -m1 iPhone \
      | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild -scheme Cutin -destination "platform=iOS Simulator,id=$DEV" \
  -derivedDataPath /tmp/dd-social build          # 서명 필요
xcrun simctl install $DEV /tmp/dd-social/Build/Products/Debug-iphonesimulator/Cutin.app
SIMCTL_CHILD_SOCIAL_CHECK=1 xcrun simctl launch --console-pty $DEV com.sapurepo.cutin

rm Cutin/Friends/SocialHarness.swift   # CutinApp의 훅도 지운다
pkill -f socialstub.py
```

## 음성 대조군

`SocialStore.toggleFollow`에서 두 오퍼레이션을 다시 하나로 묶습니다.

```swift
let result = try await client.send(
    profile.following ? .delete : .post, "/users/\(id.path)/follow",
    as: FollowResult.self
)
```

```
FAIL  팔로잉이 풀렸다
FAIL  친구도 풀렸다
=== 결과: 실패 2건 ===
```

## 결과 (2026-08-13 · iPhone 17 Pro · iOS 26.5)

- 정상: **46 PASS / 0 FAIL**
- 음성 대조군(팔로우·언팔로우를 한 호출로): **실패 2건**

## 만드는 중에 하니스가 잡은 것

- **스텁이 쿼리스트링째로 id를 잘랐다** — `self.path`에는 `?cursor=…`가 붙어 있어서
  댓글 둘째 페이지의 post id에 커서가 섞였고, 빈 목록이 돌아왔습니다. `urlparse`로 경로만
  떼도록 고쳤습니다. 첫 페이지는 쿼리가 없어 통과했기 때문에 **페이징을 검사하지 않았으면
  드러나지 않았을** 자리입니다.

## 이 하니스가 보지 않는 것

- **화면** — 검색 디바운스, 차단 확인 대화상자, 댓글 입력창과 키보드, 반응 칩 배치.
  실기기·시뮬레이터에서 눈으로 확인할 항목입니다.
- **갈래 전환** — 친구/팔로워/팔로잉 세그먼트를 바꿀 때 목록이 실제로 갈리는지. 하니스는 세
  경로를 각각 확인하지만 화면 전환은 눈으로 볼 항목입니다.

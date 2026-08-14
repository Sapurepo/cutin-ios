# 포스트 생애주기 · 피드 검증

발행 파이프라인(`PostPublisher`)과 서버 포스트 상태(`PostStore`)를 확인하는 도구입니다.
**이 폴더는 앱 타깃에 들어가지 않습니다.**

## 왜 검사하는가 — 실패가 마지막 왕복에서 드러난다

발행은 컷 4장 기준 **왕복 열여섯 번**입니다.

```
POST /posts                → draft (계정당 하나)
컷 N장 × (uploads → PUT → complete)
PATCH /posts/:id           → 컷·프레임·캡션을 붙인다
합성본 × (uploads → PUT → complete)
POST /posts/:id/publish
```

서버가 단계마다 거절 조건을 갖습니다.

- `POST /posts`는 계정당 draft 하나만 만듭니다 — 두 번째는 **409 `DRAFT_ALREADY_EXISTS`**
- `PATCH`의 `cuts`는 **ready이고 kind가 cut인 내 미디어**만 받습니다
- `publish`는 컷이 템플릿 수만큼 차 있고 합성본이 ready여야 합니다

순서가 하나라도 어긋나면 **마지막 왕복에서** 실패합니다. 사용자에게는 "컷을 다 찍었는데
저장이 안 된다"로 보이고, 그 시점에는 이미 컷 네 장이 서버에 올라가 있습니다.

## 가장 중요한 시나리오 — 남은 draft ⚠️

발행이 중간에 끊기면 **서버에 draft가 남습니다.** 그 상태에서 다시 저장을 누르면 `POST /posts`가
409로 거절되고, 처리하지 않으면 **사용자는 영영 저장할 수 없습니다** — 앱을 지웠다 깔아도
계정에 남아 있는 draft라 그대로입니다.

`PostPublisher`는 409를 만나면 `GET /posts/draft`로 넘어가 그 draft를 이어 씁니다.
지우고 새로 만드는 방법도 있지만 이미 올라간 컷을 버리게 되고, `PATCH`의 `cuts`가 통째로
교체라 이어 쓰는 쪽이 항상 옳은 상태로 수렴합니다.

## 스텁이 관대하지 않은 이유

`poststub.py`는 위 거절 조건을 그대로 흉내냅니다. 그래서 **통과 자체가 순서의 증거**입니다.
페이지 크기도 2로 작게 둬 커서 페이징이 실제로 여러 번 돕니다.

## 검사 항목

| | 시나리오 | 보는 것 |
|---|---|---|
| ① | 발행 한 바퀴 | 각 왕복 1회 · 컷 인덱스 0..N · 캡션·프레임은 PATCH에 · 공개 범위는 publish에 |
| ② | **남은 draft 이어 쓰기** | 409 → `GET /posts/draft` → 발행까지 |
| ③ | 컷 부족 | 서버가 막고 **서버 문구**를 그대로 받는지 |
| ④ | 커서 페이징 | 세 페이지 · 중복 없음 · 끝난 뒤 멈춤 · 새로고침이 첫 페이지로 |
| ⑤ | 보관 | 서버가 준 상태를 쓰는지 · 해제 후 목록에서 빠지는지 |
| ⑥ | 삭제·공유 | 세 목록에서 빠지는지 · 404 뒤 되살아나지 않는지 · 공유 링크 |

## 절차

```bash
python3 Scripts/posts/poststub.py 8769 &
cp Scripts/posts/PostsHarness.swift Cutin/Feed/

# CutinApp의 init()에 한 줄 (커밋하지 않는다)
#   #if DEBUG
#   if PostsHarness.isRequested { Task { await PostsHarness.run() } }
#   #endif

DEV=$(xcrun simctl list devices available | grep -A9 "iOS 26" | grep -m1 iPhone \
      | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild -scheme Cutin -destination "platform=iOS Simulator,id=$DEV" \
  -derivedDataPath /tmp/dd-posts build          # 서명 필요 — restore()가 Keychain을 읽는다
xcrun simctl install $DEV /tmp/dd-posts/Build/Products/Debug-iphonesimulator/Cutin.app
SIMCTL_CHILD_POSTS_CHECK=1 xcrun simctl launch --console-pty $DEV com.sapurepo.cutin

rm Cutin/Feed/PostsHarness.swift   # CutinApp의 훅도 지운다
pkill -f poststub.py
```

## 음성 대조군

`PostPublisher.draft`에서 409 처리를 지웁니다.

```swift
- } catch let error as APIError where error.isConflict {
-     return try await client.send(.get, "/posts/draft", as: Post.self)
- }
```

```
FAIL  이어 쓰기가 던졌다: server(status: 409, code: "DRAFT_ALREADY_EXISTS", …)
=== 결과: 실패 1건 ===
```

## 결과 (2026-08-13 · iPhone 17 Pro · iOS 26.5)

- 정상: **33 PASS / 0 FAIL**
- 음성 대조군(409 처리 제거): **실패 1건**

## 만드는 중에 하니스가 잡은 것

- **`APIError.Code` 열거형으로 409를 가를 수 없다.** 서버가 내는 코드는 `CONFLICT`가 아니라
  `DRAFT_ALREADY_EXISTS`입니다. 계약상 `code`는 자유 문자열이고(`ErrorResponseDto.code: string`),
  8개 열거값은 **프레임워크가 내는 일반 코드**일 뿐입니다. 분기는 HTTP 상태로 바꿨습니다.
- **보관 해제 뒤 목록에 남음** — 커서만 지우고 id를 남겨 두면 다음 로드가 "더 받기"로 들어가
  옛 id 위에 붙습니다. `List.invalidate()`가 id까지 비웁니다.

## 이 하니스가 보지 않는 것

- **화면** — 카드·상세·그리드의 `AsyncImage` 로딩, 당겨서 새로고침, 마지막 카드에서 다음 페이지가
  실제로 불리는지. 실기기·시뮬레이터에서 눈으로 확인할 항목입니다.
- **사진 앱 저장 · 시스템 공유 시트** — 권한 대화상자와 시스템 UI가 필요합니다.
- **반응·댓글** — 계약에는 있고 포스트에 수치도 실려 오지만 화면이 없습니다(다음 브랜치).

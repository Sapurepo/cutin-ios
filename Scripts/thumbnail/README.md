# 대표 컷(§6.3) 검증

`Post.gridImageURL`·`Post.pinnedFirst` 순수 함수를 확인하는 도구입니다.
**이 폴더는 앱 타깃에 들어가지 않습니다.** 서버 왕복이 없어 스텁도 없습니다
(`Scripts/geometry`와 같은 방식).

## 왜 검사하는가 — 조용히 틀리는 자리 둘

**① 배열 위치로 컷을 찾으면 안 됩니다.** 계약이 `cuts` 배열의 순서를 약속하지 않습니다 —
`cutIndex` 필드가 순서의 유일한 출처입니다. `cuts[n]`으로 짜면 지금 서버(정렬해서 내려줌)에서는
통과하고, 서버가 순서를 바꾸는 날 **그리드가 조용히 다른 컷을 그립니다.** 그래서 표본이 컷
배열을 일부러 역순으로 담습니다 — 순서대로 담으면 두 구현이 같은 답을 내서 검사가 아무것도
가르지 못합니다.

**② `sorted`로 고정을 앞으로 보내면 안 됩니다.** Swift의 `sorted`는 안정성을 보장하지 않아
같은 그룹 안의 발행 순서가 은근히 섞일 수 있습니다. filter 둘을 잇는 것이 자명하게 안정입니다.

## 검사 항목

| | 보는 것 |
|---|---|
| ① | 지정 인덱스를 `cutIndex`로 찾음(역순 배열) · 미지정 → 첫 컷 · 없는 인덱스 → 가장 앞 컷 · 컷 없음 → 합성본 → nil · `isPinned` 판정 |
| ② | 고정 앞으로 + **그룹 안 발행 순서 보존** · 빈 목록 · 고정 없음 · 전부 고정 |

## 절차

```bash
cp Scripts/thumbnail/ThumbnailHarness.swift Cutin/Feed/

# CutinApp의 init() 첫 줄에 (커밋하지 않는다)
#   #if DEBUG
#   if ThumbnailHarness.isRequested { ThumbnailHarness.run() }
#   #endif

DEV=$(xcrun simctl list devices available | grep -A9 "iOS 26" | grep -m1 iPhone \
      | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild -scheme Cutin -destination "platform=iOS Simulator,id=$DEV" \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/dd-thumb build
xcrun simctl install $DEV /tmp/dd-thumb/Build/Products/Debug-iphonesimulator/Cutin.app
SIMCTL_CHILD_THUMBNAIL_CHECK=1 xcrun simctl launch --console-pty $DEV com.sapurepo.cutin

rm Cutin/Feed/ThumbnailHarness.swift   # CutinApp의 훅도 지운다
```

## 음성 대조군

`gridImageURL`을 배열 위치 인덱싱으로 바꿉니다 — 막으려던 바로 그 버그입니다.

```swift
- let cut = cuts.first { $0.cutIndex == wanted } ?? cuts.min { $0.cutIndex < $1.cutIndex }
+ let cut = cuts.indices.contains(wanted) ? cuts[wanted] : cuts.first
```

```
FAIL  지정 인덱스를 cutIndex로 찾는다 (배열은 역순)  — https://cut/0
FAIL  미지정이면 첫 컷(cutIndex 0) — 서버 기본과 같다  — https://cut/3
=== 결과: 실패 2건 ===
```

## 결과 (2026-08-14 · iPhone 17 Pro · iOS 26.5)

- 정상: **11 PASS / 0 FAIL**
- 음성 대조군(배열 위치 인덱싱): **실패 2건**

## 이 하니스가 보지 않는 것

- **마무리 단계의 선택 UI** — 눈으로 봅니다(고르기·다시 눌러 해제·핀 배지).
- **발행 바디에 실리는지** — `PatchPostBody.thumbnailCutIndex` 경로는 0.2.0의
  `Scripts/posts`(`checkbodies.py` 포함)가 이미 계약 수준에서 봤습니다. 이번에 새로 생긴 것은
  화면 → 플로우 → 요청의 배선뿐입니다.
- **고정이 페이지 경계를 넘는 것** — 받아 온 페이지 안에서만 참입니다. 서버 정렬 지원이
  생기면 `pinnedFirst`째로 사라집니다(0.3.0 범위 문서).

# 후속 수정 3건 검증

`release/0.2.0` 리뷰에서 나온 세 결함의 수정이 실제로 듣는지 확인하는 도구입니다.
**이 폴더는 앱 타깃에 들어가지 않습니다** — `Cutin/`만 동기화 그룹이라 여기 있는 `.swift`는
컴파일되지 않습니다. 검증할 때만 앱으로 옮겨 씁니다.

## 왜 눈으로 볼 수 없는가

세 결함 모두 **화면을 눌러서는 통과 여부를 알 수 없습니다.**

| 결함 | 증상 | 왜 눈으로 못 잡나 |
|---|---|---|
| `loadUser`의 공유 슬롯 경쟁 | 프로필 그리드에 남의 포스트가 섞인다 | 두 요청이 **겹칠 때만** 난다. 로컬 서버는 즉답이라 창이 안 생긴다 |
| 로그아웃 시 스토어 미초기화 | 다음 계정이 이전 계정 피드를 본다 | 계정이 둘 있어야 하고, 같은 계정으로 재로그인하면 정상으로 보인다 |
| 조용한 실패 | 보관·반응·팔로우 버튼이 죽은 것처럼 보인다 | 서버가 실패해야 재현된다 |

그래서 `followupstub.py`가 **사용자마다 다른 목록**을 주고, 응답을 `delay`만큼 늦춰
경쟁 창을 만들고, 계정을 바꿔 끼우고, 각 동작을 실패시킵니다.

기존 `Scripts/posts/poststub.py`로는 안 됩니다 — 그쪽은 `/users/:id/posts`가 id와 무관하게
같은 목록을 돌려주므로(작성자가 항상 `ME`) 교차 오염을 셀 수 없습니다.

## 검사 항목

| | 보는 것 |
|---|---|
| ① | 두 사용자 목록을 **동시에** 받아도 서로를 덮지 않는다 |
| ② | 같은 목록의 동시 호출 4건이 요청 **1회**로 합쳐진다(`guard !isLoading`) |
| ③ | `reset()`이 목록·커서·`hasLoaded`·포스트를 비우고, 다시 받으면 새 계정 것만 온다 |
| ④ | 보관·반응·팔로우·차단 실패가 **던져지고**, 목록의 `failure` 자리에 새지 않는다 |
| ⑤ | 계정 변경 훅(`AuthSession.onAccountChange`)이 **실제로 불린다** |

③은 **음성 대조군이 시나리오 안에 있습니다** — `reset()` 전에 한 번 더 받아 두 계정이
섞이는 것(고치기 전 동작)을 먼저 확인하고, 그다음 `reset()` 후를 확인합니다.

⑤가 없으면 ③의 통과는 아무 의미가 없습니다. `reset()`이 잘 비우는데 **아무도 부르지 않는**
상태에서도 ③은 통과하기 때문입니다. 그래서 ⑤는 `phase` 전이마다 훅이 불리는 횟수를 셉니다:

- `restoring` → `signedOut`: 부르지 **않는다**(둘 다 계정이 없다)
- 로그인 · 계정 전환 · 로그아웃: 부른다
- 같은 계정의 프로필 수정(닉네임·아바타·온보딩 완료): 부르지 **않는다** — 여기서 부르면
  이름을 고칠 때마다 피드가 비워진다

훅을 화면의 `onChange(of:)`가 아니라 `phase`의 `didSet`으로 건 이유가 이 검사입니다.
`onChange`였다면 SwiftUI가 App 콘텐츠 클로저의 관찰을 잡아 주는지에 기대게 되고, 그것을
하니스로 재려면 뷰 계층을 띄워야 합니다.

> ⑤는 `AuthSession`의 `#if DEBUG` 전용 `applyPhaseForTesting(_:)`을 씁니다. `phase`를 움직이는
> 정상 경로는 로그인·로그아웃뿐이고 카카오 로그인은 사람이 눌러야 해서, 그 하나를 열어 두는
> 편이 훅을 검증하지 않고 두는 것보다 낫다고 판단했습니다.

## 절차

```bash
# ① 스텁 서버 (스레딩 서버여야 한다 — 단일 스레드면 ①②의 경쟁이 아예 안 생긴다)
python3 Scripts/followups/followupstub.py 8770 &

# ② 하니스를 앱 타깃 안으로
cp Scripts/followups/FollowupHarness.swift Cutin/Feed/

# ③ CutinApp의 init() 첫 줄에 (커밋하지 않는다)
#      #if DEBUG
#      if FollowupHarness.isRequested { Task { await FollowupHarness.run() } }
#      #endif

# ④ 빌드 · 설치 · 실행. Keychain을 쓰지 않으므로 서명 없이 돌아간다
DEV=$(xcrun simctl list devices available | grep -A9 "iOS 26" | grep -m1 iPhone \
      | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild -scheme Cutin -destination "platform=iOS Simulator,id=$DEV" \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/dd-followup build
xcrun simctl boot $DEV 2>/dev/null || true
xcrun simctl install $DEV /tmp/dd-followup/Build/Products/Debug-iphonesimulator/Cutin.app
SIMCTL_CHILD_FOLLOWUP_CHECK=1 xcrun simctl launch --console-pty $DEV com.sapurepo.cutin

# ⑤ 되돌리기
rm Cutin/Feed/FollowupHarness.swift   # CutinApp의 훅도 지운다
pkill -f followupstub.py
```

## 음성 대조군을 반드시 돌린다

통과만 보고 끝내면 하니스가 아무것도 검사하지 않아도 통과합니다. `PostStore.loadUser`를
고치기 전 형태(임시 프로퍼티를 거치는 판)로 되돌리고 다시 돌립니다.

```swift
func loadUser(id: UUID, refresh: Bool = false) async {
    scratch = userList(id: id)
    await load(path: "/users/\(id.path)/posts", refresh: refresh,
               get: { self.scratch }, set: { self.scratch = $0 })
    userLists[id] = scratch
}
@ObservationIgnored private var scratch = List()
```

```
FAIL  A 목록에 A의 포스트만 있다  — B,B,A,A
FAIL  두 목록이 겹치지 않는다
FAIL  요청이 정확히 1회  — 실제 4회
```

`B,B,A,A`가 이 수정의 이유입니다 — A의 프로필 그리드에 **B의 포스트 두 장**이 들어가 있습니다.

⑤의 대조군은 `didSet`의 중복 방지를 빼는 것입니다.

```swift
guard oldValue.userId != phase.userId else { return }   // 이 줄을 지운다
```

```
FAIL  로그인 전 전이는 부르지 않는다  — 1회
FAIL  같은 계정의 프로필 수정은 부르지 않는다  — 3회
=== 결과: 실패 5건 ===
```

## 결과 (2026-08-14 · iPhone 17 Pro · iOS 26.5)

- 수정본: **25 PASS / 0 FAIL**
- 음성 대조군 ①②(옛 `loadUser`): **실패 3건**
- 음성 대조군 ⑤(중복 방지 제거): **실패 5건**

## 이 하니스가 보지 않는 것

- **실제 로그아웃 왕복.** `signOut()`은 `/auth/logout` + Keychain을 거칩니다. 여기서 재는 것은
  `phase`가 움직일 때 훅이 불리는가이고, 그 앞단은 `Scripts/auth`의 몫입니다.
- **화면에 문구가 실제로 그려지는지.** 던져진 오류를 `PostDetailView`·`UserProfileView`가
  `notice`에 쓰는 것은 뷰 코드라 눈으로 봅니다.

## 스텁을 만들며 밟은 것

처음 판은 `PUT /reaction`의 **요청 본문을 읽지 않았습니다.** keep-alive 연결에 그 바이트가
남아 다음 요청의 첫 줄에 섞였고, 바로 뒤 프로필 조회가
`Unsupported method ('{"type":"like"}GET')` 501로 죽었습니다. 앱 결함으로 오해하기 딱 좋은
모양이라 `_drain()`으로 모든 핸들러가 본문을 먼저 읽게 했습니다. 204도 마찬가지로 본문을
실으면 안 됩니다(`_no_content()`).

# 온보딩 검증

`AuthSession`의 온보딩 경로(§3.1)가 서버의 거절 조건과 맞물려 도는지 확인하는 도구입니다.
**이 폴더는 앱 타깃에 들어가지 않습니다** — `Cutin/`만 동기화 그룹이므로 여기 있는 `.swift`는
컴파일되지 않습니다. 검증할 때만 앱으로 옮겨 씁니다.

## 왜 검사하는가 — 함정이 둘 있다

입력칸 하나짜리 화면이지만 뒤에는 왕복이 둘이고, 그 사이에 조용히 막히는 경로가 있습니다.

**① 서버의 `isNicknameTaken`이 자기 자신을 제외하지 않습니다.**

```ts
// usersRepository.ts
where(and(sql`lower(${users.nickname}) = lower(${nickname})`, isNull(users.deletedAt)))
```

이미 저장한 이름을 다시 PATCH하면 **자기 이름에 409**가 납니다. 첫 왕복(PATCH)만 성공하고
둘째(`onboarding/complete`)가 끊긴 뒤 재시도하는 경로가 정확히 그 상황이라, 앱이 PATCH를
건너뛰지 않으면 사용자는 **다른 이름을 짓기 전까지 온보딩을 마칠 수 없습니다.**

**② `POST /users/me/onboarding/complete`는 닉네임이 없으면 거절합니다**(`NICKNAME_REQUIRED`).
순서가 뒤바뀌면 통과하지 않습니다.

## 스텁이 관대하지 않은 이유

`onboardingstub.py`는 실제 백엔드(`usersService.ts` · `nicknamePolicy.ts` · `usersSchemas.ts`)의
거절 조건을 그대로 흉내냅니다 — 자기 이름을 `taken`으로 보는 것까지 포함합니다.
관대한 스텁으로는 앱이 함정을 피하는지 시험할 수 없습니다.

## 검사 항목

| | 시나리오 | 보는 것 |
|---|---|---|
| ① | 닉네임 확인 | `invalidFormat` · `forbiddenWord` · `taken` 매핑, **스펙 밖 사유**에서 던지지 않고 raw 보존 |
| ② | 저장 → 완료 | PATCH 1 + complete 1, 기기 타임존 전달, 프로필·`onboardingCompleted` 반영 |
| ③ | **같은 이름 재제출** | PATCH를 **보내지 않고** complete만 — 위 함정 ① |
| ④ | complete 실패 → 재시도 | 1차에 이름은 저장되어 남고, 2차는 PATCH 없이 이어짐 |
| ⑤ | 서버 거절 | 409·400에서 complete까지 가지 않고, **서버 문구를 그대로** 담음 |

⑤가 중요한 이유: 앱이 문구를 따로 지으면 서버가 거절 사유를 바꿔도 화면은 옛 문장을 말합니다.
전송 실패만 앱이 문구를 갖습니다(서버가 응답을 못 준 상황이라 서버 문구가 없습니다).

## 절차

```bash
# ① 스텁 서버
python3 Scripts/onboarding/onboardingstub.py 8767 &

# ② 하니스를 앱 타깃 안으로
cp Scripts/onboarding/OnboardingHarness.swift Cutin/Auth/

# ③ CutinApp의 init()에 한 줄 (커밋하지 않는다)
#      #if DEBUG
#      if OnboardingHarness.isRequested { Task { await OnboardingHarness.run() } }
#      #endif

# ④ 서명해서 빌드 · 실행 — restore()가 Keychain을 읽는다
DEV=$(xcrun simctl list devices available | grep -A9 "iOS 26" | grep -m1 iPhone \
      | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild -scheme Cutin -destination "platform=iOS Simulator,id=$DEV" \
  -derivedDataPath /tmp/dd-onboarding build
xcrun simctl install $DEV /tmp/dd-onboarding/Build/Products/Debug-iphonesimulator/Cutin.app
SIMCTL_CHILD_ONBOARDING_CHECK=1 xcrun simctl launch --console-pty $DEV com.sapurepo.cutin

# ⑤ 되돌리기
rm Cutin/Auth/OnboardingHarness.swift   # CutinApp의 훅도 지운다
pkill -f onboardingstub.py
```

> `CODE_SIGNING_ALLOWED=NO`로 빌드하면 `SecItemAdd`가 -34018로 실패해 로그인 상태를 만들 수
> 없습니다. 자세한 내용은 `Scripts/auth/README.md`를 보세요.

## 음성 대조군

`AuthSession.completeOnboarding`의 건너뛰기 조건을 없애고 돌립니다.

```swift
- if case .signedIn(let profile) = phase, profile.nickname != nickname {
+ if true {
```

```
FAIL  PATCH를 보내지 않았다
FAIL  complete 1회
FAIL  실패 없음
FAIL  온보딩이 닫혔다
FAIL  2차: PATCH가 늘지 않았다
...
=== 결과: 실패 8건 ===
```

③과 ④가 함께 무너집니다 — 자기 이름에 409를 맞고 온보딩이 닫히지 않습니다.

## 결과 (2026-08-13 · iPhone 17 Pro · iOS 26.5)

- 정상: **29 PASS / 0 FAIL**
- 음성 대조군(건너뛰기 제거): **실패 8건**

## 이 하니스가 보지 않는 것

- **화면** — 입력 디바운스(300ms), 사유 문구, 포커스, 버튼 잠금. `OnboardingView`에 닿으려면
  카카오 로그인을 사람이 눌러야 해서 실기기 확인 항목입니다.
- **전송 실패** — `Scripts/auth`의 ⑤ 시나리오가 이미 봅니다(오프라인을 로그아웃으로 오해하지 않기).

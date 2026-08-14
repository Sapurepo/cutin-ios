# 인증 흐름 검증

`Cutin/Auth/`의 토큰 보관·재발급·재시도를 실제 HTTP로 돌려보는 도구입니다.
**앱 타깃 밖이라 컴파일되지 않습니다** — 검증할 때만 옮겨 씁니다.

## 왜 이런 게 필요한가

카카오 로그인 버튼은 사람이 눌러야 해서 자동화할 수 없습니다. 하지만 **틀리면 조용히 아픈
로직은 로그인 이후**에 있습니다.

| 시나리오 | 틀렸을 때 증상 |
|---|---|
| 401 → 재발급 → 원래 요청 재시도 | 앱을 오래 켜 두면 화면이 빈다 |
| 동시 401 여러 건 → 재발급 **1회** | 서버가 리프레시 토큰을 회전하면 나머지가 폐기된 토큰으로 실패 |
| 재발급 실패 → 로그아웃 + Keychain 비움 | 죽은 토큰으로 무한히 재시도 |
| 전송 실패는 로그아웃이 **아니다** | 비행기 모드로 앱을 켠 사용자가 로그인 화면에 갇힌다 |
| 두 번째 `save`가 덮어쓴다 | 계정을 바꿔 로그인했는데 이전 계정으로 붙는다 |

`authstub.py`가 이 상황들을 만들어 주고, 재발급 횟수를 세서 `/__state`로 알려줍니다.

## ⚠️ 서명 없이 빌드하면 Keychain을 쓸 수 없다

`CODE_SIGNING_ALLOWED=NO`(README의 컴파일 검증 명령)로 빌드한 앱은 엔타이틀먼트가 없어
`SecItemAdd`가 **-34018**(`errSecMissingEntitlement`)로 실패합니다. 처음 이걸로 돌렸다가
Keychain 관련 검사 8건이 전부 실패했고, 코드가 아니라 빌드 방식이 원인이었습니다.

**서명을 켜고 빌드하세요** (`CODE_SIGNING_ALLOWED=NO`를 빼면 됩니다).
하니스가 OSStatus를 찍고 -34018이면 그 이유를 알려줍니다.

## 절차

```bash
# ① 스텁 서버 (스레딩 서버여야 한다 — 단일 스레드면 동시 401 경쟁이 아예 생기지 않는다)
python3 Scripts/auth/authstub.py 8765 &

# ② 하니스를 앱 타깃 안으로
cp Scripts/auth/AuthHarness.swift Cutin/Auth/

# ③ CutinApp의 init()에 한 줄 (커밋하지 않는다)
#      #if DEBUG
#      if AuthHarness.isRequested { Task { await AuthHarness.run() } }
#      #endif

# ④ 서명을 켜고 빌드 · 실행
DEV=$(xcrun simctl list devices available | grep -A9 "iOS 26" | grep -m1 iPhone \
      | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild -scheme Cutin -destination "platform=iOS Simulator,id=$DEV" \
  -derivedDataPath /tmp/dd-auth build
xcrun simctl install $DEV /tmp/dd-auth/Build/Products/Debug-iphonesimulator/Cutin.app
SIMCTL_CHILD_AUTH_CHECK=1 xcrun simctl launch --console-pty $DEV com.sapurepo.cutin

# ⑤ 되돌리기
rm Cutin/Auth/AuthHarness.swift   # CutinApp의 훅도 지운다
pkill -f authstub.py
```

`NSAllowsLocalNetworking`이 Info.plist에 있어야 `http://127.0.0.1`에 붙습니다 — 이미 있습니다.

## 음성 대조군을 반드시 돌린다

전부 PASS만 보고 끝내면 하니스가 아무것도 검사하지 않아도 통과합니다.
`APIClient.refreshedToken()`에서 진행 중인 작업 재사용을 지우고 돌려보세요.

```swift
// 지웠을 때
if let refreshTask { return try await refreshTask.value }
```

```
FAIL  재발급은 한 번만  — 실제 8
```

이 값이 8로 나오지 않으면 시나리오 ③이 경쟁을 만들지 못하고 있는 것입니다
(스텁의 `refreshDelay`를 늘려 창을 넓히세요).

## 카카오 로그인 자체는 실기기 확인 항목

시뮬레이터에는 카카오톡이 없어 항상 웹 로그인 경로를 탑니다. 실기기에서 확인할 것:

- 카카오톡이 깔린 기기에서 앱 전환 로그인이 되돌아오는지 (`onOpenURL` → `KakaoLogin.handle`)
- 로그인 창을 닫았을 때 오류 문구가 **뜨지 않는지** (취소는 실패가 아니다)
- 카카오톡에 로그인돼 있지 않은 기기에서 웹 로그인으로 내려가는지

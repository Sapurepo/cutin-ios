# 알림 · 디바이스 검증

인앱 알림(`NotificationStore`)과 푸시 등록(`PushRegistrar`)을 확인하는 도구입니다.
**이 폴더는 앱 타깃에 들어가지 않습니다.**

## ⚠️ 아직 알림이 오지 않습니다

서버는 준비됐습니다 — APNs 발송 구현(`shared/push/apnsPushService.ts`)이 있고 자격증명
4종(env)을 채우면 실제로 보냅니다. 남은 것은 **앱의 Push Notifications 자격(entitlement)**
입니다. 추가하려면 pbxproj를 만져야 하는데, 릴리즈당 한 브랜치만 pbxproj를 건드린다는
규칙이 있어 릴리즈 준비 브랜치의 몫입니다. 자격이 없으면 `registerForRemoteNotifications()`가
토큰 대신 오류를 줍니다(`AppDelegate`가 그 오류를 로그로 남깁니다).

서버 구현과 함께 `POST /devices` 계약이 바뀌었습니다 — `pushEnvironment`(`sandbox` /
`production`)가 **필수**입니다(없으면 400). 토큰은 한 APNs 환경에서만 유효해서
(sandbox 토큰을 production으로 보내면 `BadDeviceToken`), 빌드를 만든 쪽만 아는 값을
클라이언트가 알려줍니다. 판정은 `PushRegistrar.pushEnvironment` — 프로비저닝 프로파일의
`aps-environment`가 `development`면 sandbox, 그 외·프로파일 없음(App Store)은 production,
시뮬레이터는 sandbox입니다.

그래서 이 하니스는 **토큰이 생겼을 때 서버에 제대로 들어가는지**까지만 봅니다.

## 왜 검사하는가 — 조용히 틀리는 자리 셋

**① 미읽음 수를 목록에서 세면 안 됩니다.** `readAt == nil`을 세면 **받아 온 페이지 안에서만**
참이라, 스크롤하지 않은 사용자에게는 항상 페이지 크기 이하로 보입니다. 서버에
`GET /notifications/unread-count`가 따로 있습니다.

**② 읽음은 한 번에 100개까지**입니다(`maxItems`). 넘겨 보내면 400이고, 그러면 읽은 알림이
**영영 안 읽음으로 남습니다** — 다음에 열어도 같은 요청이 같은 이유로 실패합니다.

**③ 슬롯은 하나 이상**이어야 합니다(`minItems: 1`). "알림 끄기"는 슬롯 비우기가 아니라
`pushEnabled: false`입니다. 마지막 슬롯을 끄려는 시도는 보내지 않고 막습니다.

## 검사 항목

| | 시나리오 | 보는 것 |
|---|---|---|
| ① | 목록·미읽음 | 커서 페이징 · 중복 없음 · **미읽음은 서버가 센 값**(목록에서 세면 2, 정답은 5) |
| ② | 읽음 | 본 것이 없으면 왕복 안 함 · **본 것만** 보냄 · 읽은 것은 다시 안 보냄 |
| ③ | **100개 상한** | 250개를 세 번에 나눠 보내는지 · 한 호출 최대가 100 이하인지 |
| ④ | 설정 | 기본값 · **빈 슬롯은 보내지 않음** · 끄기는 `pushEnabled`로 |
| ⑤ | 디바이스 | **토큰을 16진으로** · 플랫폼·**환경(sandbox)**·타임존 · 해제 후 다시 안 보냄 |
| ⑥ | 계정 전환 | `reset()`이 목록·배지·`pendingRead`를 비움 · **뒤늦은 응답을 버림** · 이후 로드가 막히지 않음 |

⑤의 첫 항목: `Data`를 그대로 문자열로 만들면 `4 bytes` 같은 설명이 됩니다. APNs 토큰은
16진 문자열이어야 서버가 씁니다.

## 절차

```bash
python3 Scripts/notifications/notifystub.py 8771 &
cp Scripts/notifications/NotificationsHarness.swift Cutin/Notifications/

# CutinApp의 init()에 한 줄 (커밋하지 않는다)
#   #if DEBUG
#   if NotificationsHarness.isRequested { Task { await NotificationsHarness.run() } }
#   #endif

DEV=$(xcrun simctl list devices available | grep -A9 "iOS 26" | grep -m1 iPhone \
      | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild -scheme Cutin -destination "platform=iOS Simulator,id=$DEV" \
  -derivedDataPath /tmp/dd-notify build          # 서명 필요
xcrun simctl install $DEV /tmp/dd-notify/Build/Products/Debug-iphonesimulator/Cutin.app
SIMCTL_CHILD_NOTIFY_CHECK=1 xcrun simctl launch --console-pty $DEV com.sapurepo.cutin

rm Cutin/Notifications/NotificationsHarness.swift   # CutinApp의 훅도 지운다
pkill -f notifystub.py
```

> ③이 250개를 2개씩 받아 오므로 다른 하니스보다 오래 걸립니다(30초 안팎).

## 음성 대조군

`NotificationStore.flushRead`에서 100개 분할을 없앱니다.

```swift
- let batches = Array(pendingRead).chunked(into: 100)
+ let batches = [Array(pendingRead)]
```

```
FAIL  세 번에 나눠 보냈다
FAIL  한 호출의 최대가 100 이하
FAIL  미읽음이 0
=== 결과: 실패 3건 ===
```

미읽음이 0이 되지 않는 것이 실제 증상입니다 — 서버가 400을 내고 읽음이 반영되지 않습니다.

⑥은 v0.2.0 후속(#26)의 계정 전환 패턴을 알림에 적용한 것입니다. `pendingRead`가 남으면
**다음 계정의 토큰으로 남의 알림을 읽음 처리**하러 가고, `isLoading`을 내리지 않으면 로드 중
전환 뒤 다음 로드가 영영 막힙니다 — 둘 다 이 시나리오가 실제로 잡았습니다.

⑥의 음성 대조군은 `load`의 세대 검사를 빼는 것입니다.

```
FAIL  뒤늦은 응답을 버린다
FAIL  이후 요청은 정상으로 채워진다
=== 결과: 실패 2건 ===
```

⑤의 음성 대조군은 `submit(token:)`이 잘못된 환경 값을 보내게 하는 것입니다
(`pushEnvironment: "dev"`). 스텁이 서버처럼 400을 내고 등록이 거절됩니다.

```
FAIL  환경을 실었다 — 시뮬레이터는 sandbox
=== 결과: 실패 1건 ===
```

## 결과 (2026-08-14 · iPhone 17 Pro · iOS 26.5)

- 정상: **37 PASS / 0 FAIL**
- 음성 대조군(읽음 분할 제거): **실패 3건** (2026-08-13 기록)
- 음성 대조군(세대 검사 제거): **실패 2건** (2026-08-14 기록)
- 음성 대조군(잘못된 pushEnvironment): **실패 1건**

## 이 하니스가 보지 않는 것

- **실제 푸시** — 앱 자격(entitlement)과 서버의 APNs 자격증명 4종이 남아 있습니다.
- **권한 대화상자** — `UNUserNotificationCenter`가 사람에게 묻습니다.
- **화면** — 피드 툴바의 종과 점 배지, 알림 목록의 읽음 표시, 설정 토글.
- **`GET /health`** — 운영용 프로브라 앱에서 부를 자리가 없습니다. 계약 타입만 두었습니다.

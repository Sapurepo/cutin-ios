# 알림 · 디바이스 검증

인앱 알림(`NotificationStore`)과 푸시 등록(`PushRegistrar`)을 확인하는 도구입니다.
**이 폴더는 앱 타깃에 들어가지 않습니다.**

## ⚠️ 아직 알림이 오지 않습니다

계약은 다 붙였지만 **양쪽에 남은 일이 있습니다.**

1. **앱** — Push Notifications 자격(entitlement)이 없습니다. 추가하려면 pbxproj를 만져야 하는데,
   릴리즈당 한 브랜치만 pbxproj를 건드린다는 규칙이 있어 릴리즈 준비 브랜치의 몫입니다.
   자격이 없으면 `registerForRemoteNotifications()`가 토큰 대신 오류를 줍니다
   (`AppDelegate`가 그 오류를 로그로 남깁니다).
2. **서버** — `PushService`가 인터페이스뿐이고 APNs 구현이 없습니다.
   `shared/push/pushService.ts` 머리말에 "APNs가 확정되기 전까지 인터페이스로만 다룬다"고
   적혀 있습니다.

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
| ⑤ | 디바이스 | **토큰을 16진으로** · 플랫폼·타임존 · 해제 후 다시 안 보냄 |

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

## 결과 (2026-08-13 · iPhone 17 Pro · iOS 26.5)

- 정상: **30 PASS / 0 FAIL**
- 음성 대조군(분할 제거): **실패 3건**

## 이 하니스가 보지 않는 것

- **실제 푸시** — 위의 두 가지가 남아 있습니다.
- **권한 대화상자** — `UNUserNotificationCenter`가 사람에게 묻습니다.
- **화면** — 피드 툴바의 종과 점 배지, 알림 목록의 읽음 표시, 설정 토글.
- **`GET /health`** — 운영용 프로브라 앱에서 부를 자리가 없습니다. 계약 타입만 두었습니다.

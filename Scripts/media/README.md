# 미디어 업로드 검증

이미지 업로드(`media` 4개 오퍼레이션)와 그 첫 소비처인 아바타(§3.4)를 확인하는 도구입니다.
**이 폴더는 앱 타깃에 들어가지 않습니다.**

## 왜 검사하는가 — 순서가 전부다

```
① POST /media/uploads        목적지 발급 (pending 미디어가 생긴다)
② PUT  {url}                 바이트 전송 — [auth]라 Bearer가 필요하다
③ POST /media/{id}/complete  크기를 알려 ready로 만든다
```

틀렸을 때 증상이 조용합니다.

- **③을 빠뜨리면** 미디어가 pending으로 남고, 서버는 pending을 포스트·프로필에 붙이지 못하게
  막습니다(`MEDIA_NOT_READY`). 화면에서는 "올라갔는데 안 붙는다"로 보입니다.
- **②에 인증을 빠뜨리면** 401입니다. `POST /media/uploads`가 준 `headers`에는 Content-Type만
  오고 Authorization은 없습니다 — presigned S3가 아니라 **서버 자신의 엔드포인트**라서 그렇습니다.
- **`complete`에 포인트 크기를 보내면** 서버가 그 값을 그대로 믿어 상세 화면 비율이 어긋납니다.
  `UIImage.size`는 포인트, 바이트는 픽셀입니다.

## 스텁이 관대하지 않은 이유

`mediastub.py`는 실제 서버처럼 **상태 기계**입니다: 바이트가 오기 전에 `complete`하면 거절하고,
ready가 아닌 미디어를 프로필에 붙이면 `MEDIA_NOT_READY`를 냅니다. 관대한 스텁으로는 순서를
시험할 수 없습니다. 업로드 상한도 서버와 같은 15MB(`appSetup.ts`)입니다.

## 검사 항목

| | 시나리오 | 보는 것 |
|---|---|---|
| ① | 세 왕복 | 각 1회 · kind·mime 전달 · **서버가 준 Content-Type** · **PUT에 Bearer** · 바이트 전송 |
| ② | 크기 | `complete`에 **픽셀**(포인트 아님)을 싣는지 — scale 3 표본으로 확인 |
| ③ | 아바타 종단 | 업로드 → PATCH 순서, 프로필에 사진이 붙는지 |
| ④ | 업로드 중 401 | 재발급 1회 + PUT 재시도, 업로드가 끝까지 가는지 |
| ⑤ | 사진 지우기 | `avatarMediaId: null`이 실제로 지우는지 |
| ⑥ | 다운샘플 | 긴 변 상한 · 비율 유지 · 망가진 바이트는 nil |

④가 중요한 이유: 컷을 여러 장 올리는 동안 액세스 토큰이 만료되는 것은 흔한 일이고, 업로드는
JSON 경로가 아니라 별도 경로를 타므로 401 처리를 따로 얻지 못하면 그 자리에서 실패합니다.

## 절차

```bash
python3 Scripts/media/mediastub.py 8768 &
cp Scripts/media/MediaHarness.swift Cutin/Network/

# CutinApp의 init()에 한 줄 (커밋하지 않는다)
#   #if DEBUG
#   if MediaHarness.isRequested { Task { await MediaHarness.run() } }
#   #endif

DEV=$(xcrun simctl list devices available | grep -A9 "iOS 26" | grep -m1 iPhone \
      | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild -scheme Cutin -destination "platform=iOS Simulator,id=$DEV" \
  -derivedDataPath /tmp/dd-media build          # 서명 필요 — restore()가 Keychain을 읽는다
xcrun simctl install $DEV /tmp/dd-media/Build/Products/Debug-iphonesimulator/Cutin.app
SIMCTL_CHILD_MEDIA_CHECK=1 xcrun simctl launch --console-pty $DEV com.sapurepo.cutin

rm Cutin/Network/MediaHarness.swift   # CutinApp의 훅도 지운다
pkill -f mediastub.py
```

## 음성 대조군

`MediaUploader.upload`에서 ③(`complete`)을 빼고 목적지 정보로 `Media`를 지어내 돌려줍니다.

```
FAIL  ③ complete 1회
FAIL  ready 미디어를 돌려받았다
FAIL  프로필에 사진이 붙었다
...
=== 결과: 실패 8건 ===
```

스텁이 pending 미디어를 프로필에 붙여 주지 않으므로, ③을 빠뜨린 것이 ③번 시나리오에서 잡힙니다.

## 결과 (2026-08-13 · iPhone 17 Pro · iOS 26.5)

- 정상: **25 PASS / 0 FAIL**
- 음성 대조군(`complete` 생략): **실패 8건**

## 만드는 중에 하니스가 잡은 것

- **스텁 데드락** — `_authorized()`가 이미 잡은 락을 다시 잡아 PUT이 60초 타임아웃으로 죽었습니다.
- **스텁이 본문을 안 읽어 keep-alive 연결이 깨짐** — `/auth/refresh`가 요청 본문을 비우지 않아,
  다음 요청이 `{"refreshToken":"R1"}PUT /media/...`로 파싱돼 501이 났습니다. 재발급 뒤 재시도를
  검사하는 ④가 아니었으면 드러나지 않았을 자리입니다.
- **`UUID.uuidString`이 대문자** — 서버는 소문자 정규형을 줍니다. postgres의 `uuid` 컬럼은 둘 다
  받아 실제 서버에는 붙지만, 서버가 준 표기로 돌려보내도록 `UUID.path`를 두었습니다.

## 이 하니스가 보지 않는 것

- **사진 고르기** — `PhotosPicker`는 사람이 눌러야 합니다. 권한 키가 필요 없다는 점(별도 프로세스)은
  실기기에서 확인할 항목입니다.
- **`GET /media/content/{path}`** — 인증 없는 이미지 조회. `AsyncImage`가 직접 부르며,
  스텁은 바이트를 돌려주지만 하니스는 화면을 그리지 않습니다.

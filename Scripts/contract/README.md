# 서버 계약 검증

`Cutin/Network/`의 계약 타입이 실제 서버 스키마와 맞는지 확인하는 도구입니다.
**이 폴더는 앱 타깃에 들어가지 않습니다** — `Cutin/`만 동기화 그룹이므로 여기 있는 `.swift`는
컴파일되지 않습니다. 검증할 때만 앱으로 옮겨 씁니다.

테스트 타깃이 없는 동안 계약을 검사하는 유일한 수단입니다.

## 왜 픽스처를 손으로 쓰지 않는가

손으로 쓴 JSON으로 디코드를 시험하면 **Swift 타입이 아니라 내 가정을 시험**합니다. 둘이
똑같이 틀려도 통과합니다. 그래서 페이로드를 서버가 산출한 `openapi.json`에서 **생성**합니다.

## openapi.json

`cutin-backend` `feature/frame-decor`에서 뽑은 스냅샷입니다.

> ⚠️ 이 브랜치는 **아직 병합 전**입니다(프레임 장식 · 촬영 영상 QR). 리뷰에서 바뀌면 스냅샷을
> 다시 뽑아야 합니다. 병합되면 이 문구를 지우고 커밋 해시를 적으세요.

```bash
# 갱신할 때 (cutin-backend에서)
pnpm install && pnpm openapi:export     # DB 연결 없이 산출된다
```

서버 스키마가 바뀌면 이 파일을 갈고 아래를 다시 돌립니다. 이 스냅샷이 있어서 백엔드를
설치하지 않고도 검증할 수 있습니다.

## 절차

```bash
# ① 스펙에서 픽스처 생성 → 앱 타깃 안으로
python3 Scripts/contract/genfixtures.py Scripts/contract/openapi.json \
  > Cutin/Network/ContractFixtures.generated.swift
cp Scripts/contract/ContractHarness.swift Cutin/Network/

# ② CutinApp에 진입점을 한 번 심는다 (커밋하지 않는다)
#    struct CutinApp 안에:
#      init() {
#          #if DEBUG
#          if ContractHarness.isRequested { ContractHarness.run() }
#          #endif
#      }

# ③ 빌드 · 설치 · 실행 (배포 타깃 26.0이라 iOS 26 시뮬레이터가 필요하다)
DEV=$(xcrun simctl list devices available | grep -A9 "iOS 26" | grep -m1 iPhone \
      | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild -scheme Cutin -destination "platform=iOS Simulator,id=$DEV" \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/dd-contract build
xcrun simctl install $DEV /tmp/dd-contract/Build/Products/Debug-iphonesimulator/Cutin.app
SIMCTL_CHILD_CONTRACT_CHECK=1 xcrun simctl launch --console-pty $DEV com.sapurepo.cutin \
  > /tmp/contract.txt 2>&1

# ④ 응답 디코드 결과 + 요청 바디 대조
grep -E "^(PASS|FAIL)|결과" /tmp/contract.txt
python3 Scripts/contract/checkbodies.py Scripts/contract/openapi.json /tmp/contract.txt

# ⑤ 앱 타깃에서 다시 뺀다
rm Cutin/Network/{ContractFixtures.generated.swift,ContractHarness.swift}
#    CutinApp의 init()도 지운다
```

`SIMCTL_CHILD_` 접두사가 필요합니다 — 없으면 환경변수가 앱까지 가지 않습니다.

## 무엇을 보는가

| 방향 | 방법 |
|---|---|
| 응답 디코드 | 스펙에서 생성한 페이로드를 계약 타입으로 디코드. 스키마마다 `full`(모든 키·nullable을 값으로)과 `sparse`(필수만·nullable을 null로) 두 가지 |
| 모르는 열거형 | 스펙에 없는 값(`status: "archived"`)을 넣어 **던지지 않고** 원시값으로 통과하는지. 던지면 서버가 값을 추가하는 날 피드가 빈다 |
| 요청 인코드 | Swift가 만든 바디를 찍어 `checkbodies.py`가 스펙과 대조 — 필수 키 누락 · 없는 키 · 타입 · 열거형 · nullable 위반 |

## 음성 대조군을 반드시 돌린다

통과만 보고 끝내면 하니스가 아무것도 검사하지 않아도 통과합니다. 일부러 깨뜨려 **실패가
나오는지** 확인하세요.

```bash
# 요청 대조기 — 5종 위반을 넣어 5건이 잡히는지
printf 'ENC UpdatePostBodyDto {"visibility":"everyone"}\nENC CreatePostBodyDto {}\n' > /tmp/ctl.txt
python3 Scripts/contract/checkbodies.py Scripts/contract/openapi.json /tmp/ctl.txt   # 종료코드 1

# 디코드 — 생성된 픽스처에서 필수 키 이름을 바꾸고(accessToken → access_token) 돌린다
```

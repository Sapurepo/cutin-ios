# 컷 배치 · 합성 검증

`CutGeometry`와 `CutCompositor`의 계산이 맞는지 확인하는 도구입니다.
**이 폴더는 앱 타깃에 들어가지 않습니다** — `Cutin/`만 동기화 그룹이므로 여기 있는 `.swift`는
컴파일되지 않습니다. 검증할 때만 앱으로 옮겨 씁니다.

배치가 서버 데이터가 되면서(`Template.slots`) 0.1.0의 `CutLayoutEngine+SelfCheck`(로컬 상수를
`assert`로 잡던 장치)가 성립하지 않습니다. 못 그리는 시드는 크래시가 아니라 목록에서 빠져야
하므로, 그 필터가 실제로 거르는지를 밖에서 확인해야 합니다.

## 검사 항목

| | 대상 | 보는 것 |
|---|---|---|
| ① | `heightPerWidth` | `"W:H"` 파싱 · 잘못된 표기 8종이 1(정사각)로 떨어지는지 |
| ② | `cells` | 셀 수 · 바깥 경계 = 그리드 · **이웃 사이 간격 = 거터** · 겹침 0 · 거터 > 셀이면 `.zero` |
| ③ | `isRenderable` | 컷 수 불일치 · 0~1 밖 · 겹침 · 면적 0 · 빈 슬롯을 거르고, 비격자 맞물림은 통과시키는지 |
| ④ | `CutCompositor.render` | 캔버스 크기가 `padding·aspectRatio·footer`에서 나오는지 |
| ⑤ | `CutCompositor.render` | **`images[i]`가 슬롯 i번에 그려지는지** — 단색 컷을 넣고 픽셀을 읽어 확인 |

⑤가 이 하니스를 만든 이유입니다. 프리뷰(`CutCompositor+Preview.swift`)에 컷 번호를 박아 두었지만
눈으로 보는 검사는 행 우선·열 우선 뒤집힘을 놓치기 쉽고, 4컷 정사각에서는 두 배치가 비슷해
보입니다.

⑤의 기대 좌표는 **`CutGeometry`를 쓰지 않고** 슬롯에서 직접 구합니다. `CutGeometry.cells`로
기대값을 만들면 그 함수가 순서를 뒤집어도 기대값이 같이 뒤집혀 통과합니다 — 아래 음성 대조군에서
실제로 그랬습니다.

## 서버 시드를 옮겨 적지 않는 이유

하니스 안의 템플릿·프레임은 **검사용으로 만든 값**입니다. 검사 대상이 "이 슬롯 배열이 이 좌표로
펴지는가"라서 실제 시드 값이 필요 없고, 사본을 두면 제가 옮겨 적은 값을 시험하게 됩니다.
서버가 준 값이 계약과 맞는지는 `Scripts/contract`가 봅니다.

## 절차

```bash
# ① 앱 타깃 안으로
cp Scripts/geometry/GeometryHarness.swift Cutin/Compose/

# ② CutinApp에 진입점을 한 번 심는다 (커밋하지 않는다)
#    struct CutinApp 의 init() 첫 줄에:
#      #if DEBUG
#      if GeometryHarness.isRequested { GeometryHarness.run() }
#      #endif

# ③ 빌드 · 설치 · 실행 (배포 타깃 26.0이라 iOS 26 시뮬레이터가 필요하다)
DEV=$(xcrun simctl list devices available | grep -A9 "iOS 26" | grep -m1 iPhone \
      | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild -scheme Cutin -destination "platform=iOS Simulator,id=$DEV" \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/dd-geometry build
xcrun simctl boot $DEV 2>/dev/null || true
xcrun simctl install $DEV /tmp/dd-geometry/Build/Products/Debug-iphonesimulator/Cutin.app
SIMCTL_CHILD_GEOMETRY_CHECK=1 xcrun simctl launch --console-pty $DEV com.sapurepo.cutin

# ④ 앱 타깃에서 다시 뺀다
rm Cutin/Compose/GeometryHarness.swift
#    CutinApp의 진입점도 지운다
```

> `SIMCTL_CHILD_` 접두사가 없으면 환경 변수가 앱까지 가지 않아 하니스가 조용히 지나갑니다.

## 음성 대조군

통과가 의미 있으려면 깨질 때 깨져야 합니다. `CutGeometry.cells`의 반환에 `.reversed()`를 붙여
셀 순서를 뒤집고 다시 돌립니다.

```
FAIL  grid(2,2) 가로 이웃 간격 = 8.0  got -336.0
...
FAIL  grid(2,2) 컷 순서  어긋난 슬롯 [0, 1, 2, 3]
=== 결과: 실패 10건 ===
```

②의 간격 검사와 ⑤의 순서 검사가 함께 잡습니다. 처음 판에서는 ⑤가 기대 좌표를 `CutGeometry.cells`로
구해서 ②만 잡혔고, 그래서 ⑤를 슬롯 직접 계산으로 고쳤습니다.

## 결과 (2026-08-13 · iPhone 17 Pro · iOS 26.5)

- 정상: **56 PASS / 0 FAIL**
- 음성 대조군(`cells`에 `.reversed()`): **실패 10건**

## 이 하니스가 보지 않는 것

- **서버가 실제로 내려주는 값** — `Scripts/contract`의 몫입니다.
- **`TemplateCatalog`의 왕복** — 인증 헤더·순차 요청·실패 문구. 스텁 서버가 필요하고 아직
  검증하지 않았습니다.
- **눈으로 볼 것** — 프레임 색·푸터 글자·모서리 반경은 수치로 확인할 대상이 아닙니다.
  `CutCompositor+Preview.swift`의 프리뷰 3종을 봅니다.

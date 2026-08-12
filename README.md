# cutin-ios

**CUTIN** — 사진/영상 컷을 촬영해 템플릿으로 가공·업로드하고, 친구들과 포스트를 공유·반응하는
소셜 기록 서비스의 **iOS 네이티브 클라이언트**입니다.
기능 명세는 [CUTIN-FEATURES.md](./CUTIN-FEATURES.md)를 따릅니다.

## 이 저장소의 현재 성격 — 검증용 스파이크

클라이언트는 원래 React Native(Expo) 단일 코드베이스(`Sapurepo/cutin-frontend`의 `apps/mobile`)로
착수했습니다. 이 저장소는 그것을 **iOS 네이티브(SwiftUI)로 전환할지 판단하기 위한 수직 슬라이스
스파이크**로 시작합니다. 아직 전환이 확정된 것이 아닙니다.

**검증 목표 (타임박스 2주)** — `촬영 → 필터 → N컷 합성 → 저장 → 피드 표시`를 실기기에서 한 바퀴 돌린다.

전환을 확정하려면 아래 셋이 모두 참이어야 합니다.

1. 2주 안에 위 루프가 실기기에서 동작한다.
2. 카메라 체감이 `expo-camera`보다 명확히 낫다 (셔터 랙 · 프리뷰 안정성 · burst 연사 간격).
3. Swift 작성이 "막혀서 멈추는" 수준이 아니다 (하루 이상 막힌 횟수 3회 미만).

하나라도 거짓이면 RN 코드베이스를 유지하고 이 저장소는 폐기합니다.

**범위 밖:** 인증 · 온보딩 · 친구 · 알림 · 설정 · 실서버 연동. 화면 수를 늘리지 않습니다.

## 관련 저장소

| 저장소                                                         | 역할                          |
| -------------------------------------------------------------- | ----------------------------- |
| [`cutin-ios`](https://github.com/Sapurepo/cutin-ios)           | 메인 클라이언트 (이 저장소)   |
| [`cutin-frontend`](https://github.com/Sapurepo/cutin-frontend) | 어드민 (Next.js) + 기존 RN 앱 |
| [`cutin-backend`](https://github.com/Sapurepo/cutin-backend)   | API 서버                      |

Android는 무기한 연기합니다 (명세 §0.1). 1인 개발 체제에서 네이티브 2벌은 유지할 수 없습니다.

## Requirements

- Xcode 26 이상 (iOS 26 SDK — `glassEffect` 등 Liquid Glass API 사용)
- 배포 타깃 iOS 26.0
- 외부 의존성 없음 (SPM 패키지 미사용 — 순정 AVFoundation · Core Image · SwiftUI)

## Build & Run

```bash
# 시뮬레이터 컴파일 검증 (서명 불필요)
xcodebuild -scheme Cutin -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# 실기기: Xcode로 열어서 Run — 카메라는 시뮬레이터에서 동작하지 않습니다
open Cutin.xcodeproj
```

> 서명은 Personal Team(무료 계정)이라 **7일마다 인증서가 만료**됩니다. 기기에서 앱이 실행되지
> 않으면 Xcode에서 다시 Run 하세요.

## 구조

```
Cutin/
  CutinApp.swift        @main — 앱 진입점
  RootView.swift        탭 셸 (네이티브 Liquid Glass)
  DesignSystem/         cutin-frontend packages/tokens 에서 이식한 토큰·타이포그래피
  Domain/               도메인 모델 (packages/types 에서 이식)
  Capture/              AVFoundation 커스텀 카메라 (세션 · 프리뷰 · 촬영 UI)
  Compose/              Core Image 필터 · 템플릿 레지스트리 · N컷 합성(베이킹)
  Feed/                 합성 결과 로컬 저장 및 표시
  Resources/Fonts/      Pretendard(한글) · Geist(라틴 전용)
Config/Info.plist       카메라 권한 문구 + UIAppFonts
```

`Cutin/`은 Xcode의 **file system synchronized group**입니다 — 폴더에 `.swift` 파일을 추가하면
프로젝트 파일을 건드리지 않아도 자동으로 타깃에 포함됩니다.

## 원본 대비 이식 노트

| 이식 대상       | 원본 (`cutin-frontend`)                         | 비고                                        |
| --------------- | ----------------------------------------------- | ------------------------------------------- |
| 디자인 토큰     | `packages/tokens/src/*.ts`                      | 값 그대로 복사. 공유 인프라를 만들지 않음   |
| 도메인 모델     | `packages/types/src/cutin.ts`                   | 스파이크에 필요한 타입만                    |
| 보정 필터 7종   | `apps/mobile/src/features/capture/filters.ts`   | 4x5 컬러 매트릭스 → `CIColorMatrix`         |
| 템플릿 · 프레임 | `apps/mobile/src/features/capture/templates.ts` | 레이아웃 4종 × 프레임 스킨 7종              |
| 컷 배치 규칙    | `apps/mobile/src/components/cutFrame.tsx`       | flex 트리 → 단위 좌표 `CGRect` 계산         |
| 촬영 UX         | `apps/mobile/src/app/capture/camera.tsx`        | burst 3-2-1 카운트다운 · 재촬영 · 권한 폴백 |

**RN판에 없던 것: 이미지 합성(베이킹).** RN판은 `filterId`/`layout`을 메타데이터로만 저장하고 렌더
시점에 적용해서 결과물이 단일 이미지 파일로 남지 않습니다. 이 저장소는 그 단계를 실제로 구현하며,
**두 스택의 차이가 가장 큰 지점**입니다.

## 알려진 결정 사항

- **Swift 언어 모드 5.0** — 학습 단계에서 strict concurrency와 싸우지 않기 위한 의도적 선택입니다.
  스파이크가 성공해 본 개발로 넘어가면 Swift 6 모드로 올립니다.
- **번들 ID `com.sapurepo.cutin`** — 임시값입니다. App Store 제출 전에 확정하세요.
- **기본 브랜치 `dev`** — 조직 기본 설정을 따랐습니다. 다른 CUTIN 저장소는 `main`입니다.

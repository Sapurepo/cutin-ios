# cutin-ios

**CUTIN** — 사진/영상 컷을 촬영해 템플릿으로 가공·업로드하고, 친구들과 포스트를 공유·반응하는
소셜 기록 서비스의 **iOS 네이티브 클라이언트**입니다.
기능 명세는 [CUTIN-FEATURES.md](./CUTIN-FEATURES.md)를 따릅니다.

## 이 저장소의 현재 성격 — 메인 클라이언트 (전환 확정)

클라이언트는 원래 React Native(Expo) 단일 코드베이스(`Sapurepo/cutin-frontend`의 `apps/mobile`)로
착수했고, 이 저장소는 iOS 네이티브(SwiftUI) 전환을 판단하는 수직 슬라이스 스파이크로 시작했습니다.
스파이크는 `촬영 → 필터 → N컷 합성 → 저장 → 피드 표시` 루프를 실기기에서 관통했고,
**전환을 확정했습니다.** 이 저장소가 CUTIN의 메인 클라이언트입니다. RN 앱은 이식 참조원으로
보관하며 별도로 정리합니다.

> **확정 근거의 상태.** 스파이크는 판단 기준 셋을 두고 시작했습니다.
> ① 루프가 실기기에서 동작한다 ② 카메라 체감이 `expo-camera`보다 낫다(셔터 랙 · 프리뷰 안정성 ·
> burst 연사 간격) ③ Swift 작성이 막혀서 멈추는 수준이 아니다.
> **①·③은 참으로 판단했고, ②는 수치로 재보지 않은 상태로 확정했습니다.**
> 카메라 하드닝 작업에서 burst 간격을 실측해 ②의 근거를 소급 기록합니다 — 결과가 반대로 나오더라도
> 전환 결정을 되돌리지는 않되, 촬영 방식 설계를 그 수치에 맞춰 조정합니다.

### 릴리즈 0.1.0 범위 (진행 중)

MVP 1차. 백엔드(`cutin-backend`)가 아직 없으므로 **로컬 전용**으로 완성도를 올립니다.

- 5탭 셸(명세 §4.2) — 홈 피드 · 친구(준비 중 안내 + 초대 링크) · 촬영 CTA · 프로필 · 기록 보관
- 편집 3단계 분리(§6.1–6.3) — 템플릿 · 보정 · 마무리(대표 컷 + 캡션). §6.4는 업로드라 범위 밖
- draft 정책(§5.3) — 동시 1개 · 이어쓰기/폐기 · 24h 만료
- 포스트 상세 — 공유(§7.1) · 사진 앱 저장 · 보관(§7.4) · 삭제(§7.5)
- 카메라 생애주기 하드닝 · 합성 파이프라인 성능 · Swift 6 언어 모드 전환

**범위 밖 (0.2.0 — 서버 연동과 함께):** 인증 · 온보딩 · 친구 목록 · 반응 · 댓글 · 알림 · 업로드.

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

- **Swift 언어 모드 5.0 → 6.0 전환 중** — 스파이크 단계의 의도적 선택이었고, 0.1.0에서
  각 모듈을 6-clean하게 정비한 뒤 릴리즈 준비 브랜치에서 `SWIFT_VERSION`을 한 번에 올립니다.
- **번들 ID `com.sapurepo.cutin`** — 임시값입니다. App Store 제출 전에 확정하세요.
- **기본 브랜치 `dev`** — 조직 기본 설정을 따랐습니다. 다른 CUTIN 저장소는 `main`입니다.

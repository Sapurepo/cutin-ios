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
> 카메라 하드닝 작업에서 burst 간격을 실측해 ②의 근거를 소급 기록할 계획이었으나,
> **0.1.0 시점에도 여전히 미측정입니다** — 카메라는 시뮬레이터에서 동작하지 않고 실기기 측정을
> 하지 않았습니다. `CameraController`에 DEBUG 타이밍 로그가 들어 있어 실기기에서 촬영하면
> 값이 남습니다. 결과가 반대로 나오더라도 전환 결정을 되돌리지는 않되, 촬영 방식 설계를
> 그 수치에 맞춰 조정합니다.

### 릴리즈 0.1.0 범위 (구현 완료 · 실기기 검증 대기)

MVP 1차. 착수 시점에 백엔드(`cutin-backend`)가 커밋 하나뿐이었으므로 **로컬 전용**으로
완성도를 올렸습니다. 아래는 모두 `release/0.1.0`에 병합돼 있습니다.

- 5탭 셸(명세 §4.2) — 홈 피드 · 친구(준비 중 안내 + 초대 링크) · 촬영 CTA · 프로필 · 기록 보관
- 편집 3단계 분리(§6.1 · §6.2 · §6.4 일부) — 템플릿 · 보정 · 마무리(캡션 + 저장)
- draft 정책(§5.3) — 동시 1개 · 이어쓰기/폐기 · 24h 읽기 시점 만료 · 컷을 촬영 즉시 파일로
- 포스트 상세 — 공유(§7.1) · 사진 앱 저장 · 보관(§7.4) · 삭제(§7.5)
- 프로필(§8.1 로컬 범위) — 닉네임 · 3열 그리드 · 로컬에서 참인 통계만
- 카메라 생애주기 하드닝 · 합성 파이프라인 성능 · Swift 6 언어 모드 전환 완료

**0.1.0 범위 밖 (0.2.0으로):** 인증 · 온보딩 · 친구 목록 · 반응 · 댓글 · 알림 · 업로드.

**0.1.0에서 빠진 확정 항목:** §6.3 대표 컷(썸네일) 지정. 명세는 확정(🟢)이지만 구현하지
않았습니다 — 피드 · 상세 · 프로필 그리드가 모두 합성 결과를 보여주므로 대표 컷을 **읽는 화면이
없습니다.** 소비처가 생기는 시점에 넣습니다.

**남은 완료 조건:** 실기기 검증(Release 구성 전체 플로우 1회 완주 + 스크린샷). 카메라·공유·
사진 앱 저장은 시뮬레이터에서 검증할 수 없습니다.

### 릴리즈 0.2.0 범위 (진행 중) — 백엔드 실계약

`cutin-backend`에 API가 구현돼 있습니다(`feature/p5-push`, NestJS 11 + Drizzle, 11개 모듈
40여 엔드포인트). 0.1.0이 로컬로 만든 것을 **서버 계약에 맞춰 잇는 것**이 0.2.0의 일입니다.

계약 요약:

| 영역 | 계약 |
|---|---|
| 인증 | Bearer. `POST /auth/oauth/{google,kakao}` `{token}` → `{accessToken, refreshToken, expiresIn, onboardingCompleted}` |
| 페이징 | 커서. `?cursor=&limit=` → `{items, nextCursor}` |
| 업로드 | `POST /media/uploads {kind, mime}` → `{mediaId, url, method, headers}` → `PUT url` → `POST /media/:id/complete {width, height}` |
| 포스트 | `POST /posts {templateId}`(draft) → `PATCH /posts/:id`(cuts·caption·visibility·thumbnailCutIndex) → `POST /posts/:id/publish {composedMediaId}` |
| 템플릿 | `GET /templates` — `{id, code, name, cutCount, aspectRatio, slots:[{x,y,width,height}]}` |
| 열거형 | media `cut·composed·avatar` / post `draft·published·deleted` / visibility `friends·public·private` |

**서버는 아직 배포되지 않았습니다.** 저장소에 운영 주소가 없고 배포 설정 자체가 없습니다
(`docker-compose`는 로컬용, CI만 존재 · `PUBLIC_BASE_URL` 기본값이 `localhost` · 스토리지는
로컬 디스크 · `CLAUDE.md`에 "인프라 미정"). 그래서 `Config/Debug.xcconfig`는
`http://localhost:3000`을, `Release.xcconfig`는 **빈 값**을 가리킵니다 — Release는 첫 API
호출에서 크래시합니다(조용히 잘못된 주소로 붙는 것보다 낫습니다). 배포되면 한 줄만 채우면 됩니다.

**합성은 클라이언트 몫입니다.** 서버 `postSchema`의 `composed` 필드에 "iOS가 만든 합성본"이라고
적혀 있습니다 — 0.1.0의 `CutCompositor`가 그대로 쓰입니다.

#### 0.1.0의 로컬 결정과 충돌하는 지점

읽어 보면 **서버 `template`은 로컬 `CaptureTemplate`이 아니라 로컬 `CutCount`에 대응합니다.**
서버 템플릿은 컷 수와 격자만 담고(`seedTemplates.ts`의 4종), 로컬이 커스텀한 레이아웃 변형과
프레임 외형에는 대응 필드가 없습니다. 두 축을 서버로 옮기는 요청을 넣었습니다.

| 0.1.0 | 서버 계약 | 0.2.0 결정 |
|---|---|---|
| `CutCount`(1/2/4/6)·`CutLayout` 로컬 열거형 | 템플릿의 `cutCount`·`slots`가 진실. "클라이언트가 컷 수를 가정하지 않는다" | **서버 템플릿을 진실로 채택** — 로컬 열거형 제거 |
| `FrameSkin` 스킨 8종(프레임 색·패딩·거터·푸터) | 서버에 없음 | **서버가 소유** — `GET /frames` 신설 요청 ([#11](https://github.com/Sapurepo/cutin-backend/issues/11) B) |
| 레이아웃 4종(2×2·세로4·가로4·빅레프트) | `grid4` 2×2 하나뿐 | **서버에 3종 추가 요청** ([#11](https://github.com/Sapurepo/cutin-backend/issues/11) A) |
| 2컷 **가로 배치** | `strip2` **세로 스택** | 서버를 따른다. 의도 확인 요청 ([#11](https://github.com/Sapurepo/cutin-backend/issues/11) A-4) |
| 캔버스 항상 정사각 | 컷 수마다 다른 `aspectRatio` | 서버를 따른다. 다만 프레임 여백 포함 여부 정의 요청 ([#11](https://github.com/Sapurepo/cutin-backend/issues/11) C) |
| §6.3 대표 컷 미구현 | `thumbnailCutIndex` 필드 존재 | **여전히 미구현** — 아래 참고 |
| 공개 범위 UI 없음 | `visibility` 필수 열거형 | 구현했다(편집 3단계) |
| draft를 로컬 파일로 | 서버 draft(`GET /posts/draft`) | 발행 파이프라인은 서버 draft를 쓴다. 로컬 draft는 **진행 중인 촬영**으로 남는다 — 그건 이 기기의 상태다 |
| `posts.json` 로컬 인덱스 | `GET /feed` 커서 | 서버가 진실. 로컬 인덱스·JPEG 저장 계층을 걷어냈다 |
| 인증 없음(바로 피드) | 모든 엔드포인트 Bearer | **로그인 + 온보딩(닉네임)까지 넣는다.** 카카오만 — 구글은 도입 취소 |
| 기존 로컬 포스트 | — | **버린다.** 0.1.0은 실기기 검증도 안 된 개발 빌드였다 |
| `archive.json` 보관 | 착수 시점에는 API 없음 | **서버로 옮겼다** — `GET /users/me/bookmarks`가 생겼다([cutin-backend#10](https://github.com/Sapurepo/cutin-backend/issues/10)) |

> 위 표는 0.2.0 **착수 시점**의 판단입니다. 마지막 두 줄과 아래 "범위 밖"은 진행 중에
> 뒤집혔습니다 — 문서가 실제와 다른 말을 하지 않도록 결과로 고쳐 적었습니다.

#### 착수 시점에 범위 밖이라고 적었으나 들어간 것

반응·댓글·팔로우·차단·신고를 **넣었습니다.** 인증·업로드·포스트 수명주기·피드가 서고 나니
그 위에 얹는 것이 남은 일이었고, 서버 API가 이미 있었습니다.

#### 범위 밖 (0.2.0 최종)

- **알림·푸시.** 서버가 온보딩 완료 시점에 기본 슬롯을 채우지만 발송 인프라가 미정입니다.
  고르게 해도 알림이 가지 않으므로 화면을 만들지 않았습니다.
- **§6.3 대표 컷 지정.** 서버에 `thumbnailCutIndex`가 있고 발행 요청에 실을 수도 있지만
  **읽는 화면이 없습니다** — 피드·상세·프로필 그리드가 모두 합성 결과를 보여줍니다.
  0.1.0에서 넣지 않은 이유가 그대로 남아 있어 결국 넣지 않았습니다.
- **온보딩 §3.2 친구목록·§3.3 알림 슬롯·§3.5 팁 화면.** 각각 연락처 매칭 경로 없음 · 푸시
  미정 · 보여줄 팁 미정입니다. 지키지 못할 약속을 화면에 만들지 않았습니다.
- **오프라인 피드.** 서버 목록의 파일 캐시를 두지 않았습니다 — 사본을 두면 "서버에서 지운
  포스트가 기기에 남는다"를 새로 얻습니다.
- **구글 로그인.** 서버는 `google`·`kakao` 둘을 지원하지만(전자는 `id_token`을 JWKS로 검증,
  후자는 `access_token`을 kapi Bearer로 사용) 0.2.0은 카카오만 붙입니다.

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
- 외부 의존성 2개 (0.1.0까지는 0개였습니다)
  - `kakao-ios-sdk` 2.28.0 — 카카오 로그인 (`KakaoSDKCommon` · `KakaoSDKAuth` · `KakaoSDKUser`)
  - `Alamofire` 5.12.0 — **카카오 SDK의 전이 의존.** 직접 쓰지 않습니다
  - 나머지는 순정입니다 (AVFoundation · Core Image · SwiftUI · Security)
  - `pbxproj`를 건드리는 변경이라 0.1.0의 규칙 1에 맞춰 **인증 브랜치 한 곳에 몰았습니다**

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
  CutinApp.swift        @main — 앱 진입점. 전송 계층 하나와 그것을 쓰는 앱 수명 상태
                        (AuthSession·PostStore·SocialStore·CommentStore·TemplateCatalog·
                        PostPublisher·CaptureFlow)를 만들어 환경으로 내린다.
                        계정이 바뀌면 서버에서 받아 둔 것을 버린다
  RootView.swift        탭 셸 (네이티브 Liquid Glass) · 촬영 커버 · draft 차단 시트
  AppIcon.icon/         Icon Composer 레이어 문서 (iOS 26 Liquid Glass 아이콘)
  Auth/                 로그인 게이트 · 카카오 로그인 · 세션 · 토큰 보관(Keychain)
  Network/              API 기준 주소 · 오류 · 전송(actor) · Contracts/(서버 계약 타입)
  Navigation/           AppTab · Route(id를 나른다) · AppCoordinator(탭·촬영 커버 소유)
  DesignSystem/         cutin-frontend packages/tokens 에서 이식한 토큰·타이포그래피
                        + Components/ (2곳 이상에서 실제로 쓰이는 것만)
  Domain/               도메인 모델 (packages/types 에서 이식)
  Capture/              AVFoundation 커스텀 카메라 · 촬영 플로우 상태 · draft 차단 시트
  Compose/              Core Image 필터 · 서버 템플릿/프레임 목록 · 배치 계산 ·
                        N컷 합성(베이킹) · 편집 3단계 화면 · 발행 파이프라인
  Storage/              파일 접근 규칙(FileVault) · 컷 JPEG 쓰기/디코드 · draft 영속
                        (로컬에 남는 것은 **진행 중인 촬영**뿐이다)
  Feed/                 피드 · 포스트 카드 · 상세 · 서버 포스트 상태 · 댓글
  Friends/              친구·팔로우·차단(SocialStore) · 타인 프로필 · 신고
  Archive/ Profile/     나머지 탭
  Resources/Fonts/      Pretendard(한글) · Geist(라틴 전용)
Config/
  Shared.xcconfig       두 구성 공통 빌드 설정 (SWIFT_VERSION · 카카오 앱 키 포함)
  Debug/Release.xcconfig  구성별 설정 — 지금은 Shared를 include만 한다
  Info.plist            카메라·사진 앱 권한 문구 · UIAppFonts · API 기준 주소 ·
                        카카오 URL 스킴
```

```
Scripts/
  contract/             서버 계약 검증 (openapi.json 스냅샷 · 픽스처 생성기 · 바디 대조기)
  auth/                 인증 흐름 검증 — 401 재발급 · 동시 401 · Keychain
  geometry/             배치·합성 검증 — 슬롯 → 좌표 · 캔버스 크기 · 컷 순서(픽셀을 읽는다)
  onboarding/           닉네임 확인·저장 검증 — 서버 거절과 재시도 경로
  media/                업로드 왕복 셋 검증
  posts/                발행 파이프라인 · 원격 피드 · 보관 검증
  social/               친구·댓글·반응·신고 검증
  followups/            후속 수정 3건 검증 — 동시성 경쟁 · 계정 전환 · 실패 전파
```

`Scripts/`는 앱 타깃 밖이라 컴파일되지 않습니다. 테스트 타깃이 없는 동안의 유일한 실행
검증이라, 각 폴더 README에 절차와 **음성 대조군**(일부러 깨뜨려 실패가 나오는지)을 적어
뒀습니다. 통과만 보고 끝내면 하니스가 아무것도 검사하지 않아도 통과합니다.

> **Keychain은 서명 없이 검증할 수 없습니다.** 아래 컴파일 검증 명령(`CODE_SIGNING_ALLOWED=NO`)으로
> 빌드한 앱은 엔타이틀먼트가 없어 `SecItemAdd`가 -34018(`errSecMissingEntitlement`)로 실패합니다.
> 토큰 보관을 확인할 때는 서명을 켜세요.

`Cutin/`은 Xcode의 **file system synchronized group**입니다 — 폴더에 `.swift` 파일을 추가하면
프로젝트 파일을 건드리지 않아도 자동으로 타깃에 포함됩니다.

> **아이콘을 명령줄로 고칠 때.** `AppIcon.icon`은 Icon Composer 문서입니다. Xcode에서 그 문서를
> 열어 두면 편집기가 자기 형식으로 다시 저장하므로, 명령줄에서 `icon.json`을 고칠 때는 닫아
> 두세요. 렌더 확인은 Icon Composer에 딸린 CLI로 합니다 — 렌디션 6종을 뽑아볼 수 있습니다.
>
> ```bash
> "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
>   Cutin/AppIcon.icon --export-image --output-file /tmp/icon.png \
>   --platform iOS --rendition Default --width 1024 --height 1024 --scale 2
> ```
>
> 렌디션: `Default` `Dark` `TintedLight` `TintedDark` `ClearLight` `ClearDark`.
> `icon.json`의 `groups`는 **앞에서 뒤로** 그려집니다 — 배열 첫 항목이 최상단입니다.
> 레이어에 텍스트를 넣을 때는 `<text>`가 아니라 글리프 경로로 구워야 합니다(렌더 시 폰트가
> 보장되지 않습니다).

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

- **Swift 언어 모드 6.0** — 스파이크는 5.0으로 시작했고, 0.1.0에서 각 모듈을 6-clean하게
  정비한 뒤 릴리즈 준비 브랜치에서 `Config/Shared.xcconfig`의 `SWIFT_VERSION`을 한 번에
  올렸습니다. 되돌리려면 그 한 줄만 5.0으로 바꾸면 됩니다.
- **번들 ID `com.sapurepo.cutin`** — 임시값입니다. App Store 제출 전에 확정하세요.
- **기본 브랜치 `dev`** — 조직 기본 설정을 따랐습니다. 다른 CUTIN 저장소는 `main`입니다.

# UI 감사 — 전 화면 스크린샷

디자인 작업의 before/after 증거를 **같은 데이터·같은 절차**로 다시 찍기 위한 도구입니다.
**이 폴더는 앱 타깃에 들어가지 않습니다.** 결과와 판단은 `Design/`에 있습니다.

## 왜 도구인가

화면이 20개 가까이 되고 라이트/다크가 있어 손으로 찍으면 한 바퀴에 30분이고, 두 번째부터는
데이터가 달라져 비교가 안 됩니다. 시뮬레이터에는 탭 명령이 없으므로 **앱이 환경변수로 화면을
바로 열게** 하고(`AuditHook`), 로그인은 카카오 대신 **서버 비밀로 서명한 토큰**을 심습니다.

## 구성

| 파일 | 역할 |
|---|---|
| `seed/seed.py` | 로컬 서버에 사용자 5명 · 포스트 15개(템플릿·프레임 골고루) · 팔로우 · 댓글 · 반응을 **API로** 넣는다. 멱등 |
| `seed/compose.swift` | 시드용 컷·합성본 JPEG — 앱의 `CutCompositor` 규칙(프레임 padding/gutter/radius/푸터)을 흉내낸다 |
| `AuditHook.swift` + `hook.patch` | `AUDIT_TOKEN`으로 세션을 심고 `AUDIT_SCREEN`으로 화면을 연다(`catalog`는 디자인 카탈로그, `AUDIT_SECTION=buttons`처럼 절로 스크롤). **커밋하지 않는다** |
| `shoot.sh` / `shoot-all.sh` | 화면 하나 / 전부를 라이트·다크로 찍고 콘택트 시트를 만든다 |
| `montage.swift` | 스크린샷을 라벨 붙여 격자로 모은다 |

## 절차

```bash
# 0. 로컬 서버 (백엔드 워크트리에서) — Postgres는 docker compose
cd ~/orca/workspaces/cutin-backend/dev && docker compose up -d postgres && pnpm db:migrate && pnpm dev &
#    .env의 PUBLIC_BASE_URL이 http://localhost:3000 이어야 시뮬레이터가 이미지를 받는다

# 1. 시드 — '나'는 실제 로그인한 적 있는 사용자 id
CUTIN_ME=<user id> python3 Scripts/audit/seed/seed.py        # → seed/me.token, seed/out/

# 2. 훅을 앱에 심는다 (커밋 금지)
git apply Scripts/audit/hook.patch
cp Scripts/audit/AuditHook.swift Cutin/AuditHook.swift

# 3. 빌드 — base URL은 파일을 건드리지 않고 인자로 넘긴다
DEV=F4A70383-9134-477E-BCCA-B7824317EDE0
xcodebuild -scheme Cutin -destination "platform=iOS Simulator,id=$DEV" \
  -derivedDataPath /tmp/dd-audit CUTIN_API_BASE_URL='http://localhost:3000' build
xcrun simctl install $DEV /tmp/dd-audit/Build/Products/Debug-iphonesimulator/Cutin.app

# 4. 시뮬레이터 한 번만: 한국어 로케일 · 카메라 권한(TCC) · 팁 본 것으로
xcrun simctl spawn $DEV defaults write .GlobalPreferences AppleLanguages -array ko-KR en
xcrun simctl spawn $DEV defaults write .GlobalPreferences AppleLocale -string ko_KR
sqlite3 ~/Library/Developer/CoreSimulator/Devices/$DEV/data/Library/TCC/TCC.db \
  "insert or replace into access (service, client, client_type, auth_value, auth_reason, auth_version, flags) values ('kTCCServiceCamera','com.sapurepo.cutin',0,2,2,1,0);"
xcrun simctl shutdown $DEV && xcrun simctl boot $DEV       # 로케일·TCC는 재부팅해야 먹는다

# 5. 찍는다
Scripts/audit/shoot-all.sh <내 포스트 id> <타인 포스트 id> <타인 user id> Design/shots

# 6. 정리
git apply -R Scripts/audit/hook.patch && rm Cutin/AuditHook.swift
```

온보딩 화면은 서버에서 내 `onboarding_completed_at`을 잠시 NULL로 두고 `shoot.sh onboarding feed`로
찍은 뒤 되돌립니다(`update users set onboarding_completed_at=now() where id='…'`).

## 알아둘 것

- **`simctl privacy`는 카메라를 모릅니다.** 권한 대화상자가 뜨면 SpringBoard에 남아 앱을 다시 켜도
  그대로라, TCC.db에 직접 넣고 재부팅합니다.
- **키체인은 앱을 지워도 남습니다.** 로그인 화면을 찍으려면 `simctl keychain reset`.
- 편집 3단계는 `AuditHook`이 `Documents/Drafts/`에 draft 메타를 쓰고 이어쓰기로 엽니다. 컷 파일은
  `shoot-all.sh`가 컨테이너에 복사합니다. 카메라를 루트에 두지 않는 이유는 위 권한 대화상자.
- 편집 단계의 컷 파일은 `cp`가 **생성 시각을 보존**하므로 훅이 draft `createdAt`을 20시간 전으로 둡니다 —
  `DraftStore`는 draft보다 오래된 컷을 이전 촬영의 잔여로 보고 지웁니다.
- 시드 사진은 시뮬레이터 샘플 사진 6장 + macOS 배경화면 2장입니다. 실제 인물 사진이 아니라
  얼굴이 들어가는 컷의 느낌은 실기기로 봐야 합니다.

## 결과

`Design/audit-2026-08-17-{light,dark}.jpg` — 판단은 `Design/audit-2026-08-17.md`.

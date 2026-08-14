/* CUTIN 도메인 모델 — cutin-frontend `packages/types/src/cutin.ts`에서 스파이크 범위만 이식.
 * 인증·친구·알림 타입은 범위 밖이라 옮기지 않는다. */

import Foundation

/* 컷 수와 배치 열거형(`CutCount`·`CutLayout`)은 없다. 서버 템플릿이 그 둘을 갖는다 —
 * `Template.cutCount`와 `Template.slots`다. 로컬 열거형을 두면 서버가 템플릿을 늘릴 때
 * 앱을 다시 내야 하고, 서버 컨트롤러의 "클라이언트가 컷 수를 가정하지 않는다"를 어긴다.
 * 고를 수 있는 컷 수는 `TemplateCatalog.cutCounts`가 목록에서 유도한다. */

/// 촬영 방식 — 명세 §5.2 (A) 연속 촬영 / (B) 한 장씩 개별 촬영
enum CaptureMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case burst
    case single

    var id: String { rawValue }
    var label: String { self == .burst ? "연속 촬영" : "한 장씩" }
    var hint: String {
        self == .burst ? "3-2-1 카운트다운으로 이어서 찍어요" : "셔터를 누를 때마다 한 컷씩 찍어요"
    }
}

/* 저장된 포스트(`ComposedPost`)는 없다. 서버가 포스트를 갖는다 — `Contracts.swift`의 `Post`다.
 *
 * 0.1.0은 합성 결과 JPEG와 `posts.json` 인덱스가 **원본**이었다. 이제 그것은 사본이고, 사본을
 * 파일로 두면 "서버에서 지운 포스트가 기기에 남는다"를 새로 얻는다. 오프라인 피드는 범위 밖이다.
 *
 * 진행 중인 촬영(`DraftStore`)은 그대로 파일에 남는다 — 그건 이 기기의 상태이고 서버가
 * 소유할 일이 없다. */

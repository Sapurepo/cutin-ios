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

/// 합성까지 끝나 로컬에 저장된 포스트.
/// RN판 `Post`와 달리 **합성 결과 이미지 파일**을 실체로 가진다 — 두 스택의 핵심 차이.
struct ComposedPost: Identifiable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    /// Documents/Posts/ 하위 파일명
    let imageFilename: String
    /* 촬영 당시의 배치·외형을 **스냅샷으로** 들고 있는다. id만 남기면 서버가 템플릿이나
     * 프레임을 고친 뒤 옛 포스트의 메타가 실제로 구워진 그림과 어긋난다. 서버도 같은 결론이라
     * `postSchema`에 `template`·`frame` 객체를 실어 보낸다.
     *
     * 둘 다 옵셔널인 이유는 아래 `recoveredFromFile`이다 — 0.1.0은 복구 레코드에 `.four` 같은
     * 자리값을 넣었는데, 모르는 값을 아는 척하는 것보다 없다고 말하는 편이 정직하다. */
    let template: Template?
    let frame: Frame?
    let filterID: FilterID
    var caption: String
    /// 인덱스를 잃고 JPEG에서 되살린 레코드 표시. 이때 `template`·`frame`·`filterID`는
    /// 인덱스에만 있던 값이라 복구되지 않는다 — 그 값을 진짜로 오해하지 않도록 파일에 흔적을 남긴다.
    var recoveredFromFile: Bool?
}

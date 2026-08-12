/* CUTIN 도메인 모델 — cutin-frontend `packages/types/src/cutin.ts`에서 스파이크 범위만 이식.
 * 인증·친구·알림 타입은 범위 밖이라 옮기지 않는다. */

import Foundation

/// 컷 수 옵션 — 명세 §5.1
enum CutCount: Int, CaseIterable, Codable, Identifiable, Sendable {
    case one = 1
    case two = 2
    case four = 4
    case six = 6

    var id: Int { rawValue }
    var label: String { "\(rawValue)컷" }
}

/// 4컷 템플릿 레이아웃 변형 — 명세 §6.1 (4컷 외 컷 수는 2xN 기본)
enum CutLayout: String, Codable, Sendable {
    case grid2x2 = "2x2"
    /// 세로로 쌓는 포토부스 스트립 (원본 cutFrame.tsx의 `colWrap`)
    case row
    case bigLeft = "big-left"
    /// 가로로 늘어놓는 와이드 스트립 (원본의 `rowWrap`)
    case strip
}

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
    let count: CutCount
    let layout: CutLayout
    let frameID: String?
    let filterID: FilterID
    var caption: String
}

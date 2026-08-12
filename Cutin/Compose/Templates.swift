/* 촬영 템플릿 레지스트리 — cutin-frontend `apps/mobile/src/features/capture/templates.ts`에서 이식.
 * 인생네컷식 "레이아웃 × 프레임 스킨" 큐레이션.
 * 프레임 색은 콘텐츠(사진 프레임)이므로 모노크롬 디자인 토큰에 넣지 않는다. */

import SwiftUI

struct FrameSkin: Identifiable, Equatable, Sendable {
    enum Footer: String, Sendable {
        /// 하단 CUTIN 로고 + 날짜 스탬프
        case logoDate
    }

    let id: String
    /// 프레임 배경색
    let bg: Color
    /// 푸터 스탬프 텍스트 색
    let fg: Color
    /// 프레임 바깥 여백
    let padding: CGFloat
    /// 컷 사이 간격
    let gutter: CGFloat
    let cellRadius: CGFloat
    let footer: Footer?

    static func == (lhs: FrameSkin, rhs: FrameSkin) -> Bool { lhs.id == rhs.id }
}

private func stamped(id: String, bg: UInt32, fg: UInt32) -> FrameSkin {
    FrameSkin(
        id: id,
        bg: Color(hex: bg),
        fg: Color(hex: fg),
        padding: 12,
        gutter: 8,
        cellRadius: 2,
        footer: .logoDate
    )
}

enum FrameSkins {
    static let white = stamped(id: "white", bg: 0xFFFFFF, fg: 0x0A0A0B)
    static let noir = stamped(id: "noir", bg: 0x111113, fg: 0xF5F5F4)
    static let peach = stamped(id: "peach", bg: 0xFFD9CF, fg: 0x8A3B2C)
    static let butter = stamped(id: "butter", bg: 0xFFE9A8, fg: 0x7A5B12)
    static let lavender = stamped(id: "lavender", bg: 0xE3D9FF, fg: 0x4A3B7A)
    static let mint = stamped(id: "mint", bg: 0xCFEDDF, fg: 0x1F5C42)
    static let cherry = stamped(id: "cherry", bg: 0xC6373F, fg: 0xFFFFFF)

    static let all: [FrameSkin] = [white, noir, peach, butter, lavender, mint, cherry]

    /// 미지정·미지의 id면 기본 룩(nil).
    static func find(_ id: String?) -> FrameSkin? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

struct CaptureTemplate: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// 이 템플릿을 고를 수 있는 컷 수
    let counts: [CutCount]
    /// 4컷 외 컷 수에서는 컷 수 기본(2xN) 레이아웃으로 그린다
    let layout: CutLayout
    /// 미지정이면 기본(테마 surfaceSunken) 룩
    let frame: FrameSkin?

    static func == (lhs: CaptureTemplate, rhs: CaptureTemplate) -> Bool { lhs.id == rhs.id }
}

enum Templates {
    private static let everyCount: [CutCount] = [.one, .two, .four, .six]

    /// 첫 항목이 기본 템플릿 — `find()` 폴백 대상.
    static let all: [CaptureTemplate] = [
        CaptureTemplate(id: "basic", name: "베이직", counts: everyCount, layout: .grid2x2, frame: nil),
        CaptureTemplate(id: "classic-white", name: "클래식 화이트", counts: everyCount, layout: .grid2x2, frame: FrameSkins.white),
        CaptureTemplate(id: "noir-film", name: "느와르 필름", counts: everyCount, layout: .grid2x2, frame: FrameSkins.noir),
        CaptureTemplate(id: "booth-strip", name: "포토부스 스트립", counts: [.four], layout: .row, frame: FrameSkins.white),
        CaptureTemplate(id: "wide-strip", name: "와이드 스트립", counts: [.four], layout: .strip, frame: FrameSkins.noir),
        CaptureTemplate(id: "big-left", name: "빅 레프트", counts: [.four], layout: .bigLeft, frame: FrameSkins.white),
        CaptureTemplate(id: "peach", name: "피치", counts: everyCount, layout: .grid2x2, frame: FrameSkins.peach),
        CaptureTemplate(id: "butter", name: "버터", counts: everyCount, layout: .grid2x2, frame: FrameSkins.butter),
        CaptureTemplate(id: "lavender", name: "라벤더", counts: everyCount, layout: .grid2x2, frame: FrameSkins.lavender),
        CaptureTemplate(id: "mint", name: "민트", counts: everyCount, layout: .grid2x2, frame: FrameSkins.mint),
        CaptureTemplate(id: "cherry", name: "체리", counts: everyCount, layout: .grid2x2, frame: FrameSkins.cherry),
    ]

    static func forCount(_ count: CutCount) -> [CaptureTemplate] {
        all.filter { $0.counts.contains(count) }
    }

    /// 미지정·미지의 id는 기본 템플릿으로 조용히 폴백한다.
    static func find(_ id: String?) -> CaptureTemplate {
        guard let id, let match = all.first(where: { $0.id == id }) else { return all[0] }
        return match
    }
}

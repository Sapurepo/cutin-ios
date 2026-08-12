/* CUTIN 타이포그래피 — cutin-frontend `packages/tokens/src/typography.ts`에서 이식.
 * 본문/UI는 Pretendard(한글 전반), 라틴/숫자/로고는 Geist(라틴 전용 — 한글에 적용 금지).
 * 위계는 weight와 size로 만들고 색으로 만들지 않는다. */

import SwiftUI

enum FontFace {
    /// 한글 본문·UI (번들된 Pretendard)
    case body
    /// 라틴/숫자/로고 전용 (번들된 Geist)
    case latin
}

enum FontWeightToken: String {
    case regular = "Regular"
    case medium = "Medium"
    case semibold = "SemiBold"
    case bold = "Bold"
}

enum Typography {
    static func font(_ face: FontFace, _ weight: FontWeightToken = .regular, size: CGFloat) -> Font {
        .custom(postScriptName(face, weight), size: size)
    }

    private static func postScriptName(_ face: FontFace, _ weight: FontWeightToken) -> String {
        switch face {
        case .body: return "Pretendard-\(weight.rawValue)"
        case .latin: return "Geist-\(weight.rawValue)"
        }
    }

    // MARK: - typeScale (원본 값 그대로)

    static let logo = font(.latin, .bold, size: 18)
    static let headline = font(.body, .semibold, size: 17)
    static let bodyText = font(.body, .regular, size: 14)
    static let caption = font(.body, .regular, size: 11)
    static let numeric = font(.latin, .medium, size: 15)
    static let chip = font(.body, .medium, size: 12)
    /// 버튼·강조 라벨 — 원본 스케일에 없어 `font(.body, .semibold, size: 15)` 인라인 호출이
    /// 3곳(촬영 시작·촬영 방식·권한 안내)에 반복되던 것을 승격
    static let buttonLabel = font(.body, .semibold, size: 15)

    /// 로고 트래킹 — 원본 `typeScale.logo.tracking = 0.02em`
    static let logoTracking: CGFloat = 18 * 0.02
}

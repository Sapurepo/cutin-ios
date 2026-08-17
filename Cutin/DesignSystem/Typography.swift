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

    // MARK: - typeScale

    /* 0.3.0까지는 웹 원본의 여섯 단계(headline·bodyText·caption·numeric·chip·buttonLabel)뿐이라
     * 화면 제목은 시스템 largeTitle(SF)에, 절 라벨은 11px 회색 caption에 기대야 했다(감사 G2·G7).
     * 0.4.0이 위아래를 채운다. **크기는 열 단계뿐**이고 화면이 임의 크기를 부르지 않는다 —
     * 임의 호출이 필요하면 단계를 늘린다.
     *
     * 모두 `Font.custom(_:size:)`라 Dynamic Type을 body 기준으로 따라간다. */

    /// 화면 제목 — 탭 루트의 "CUTIN"·"친구"·"프로필". 시스템 largeTitle을 대신한다
    static let largeTitle = font(.body, .bold, size: 28)
    /// 절 제목 · 시트 제목
    static let title = font(.body, .semibold, size: 22)
    static let headline = font(.body, .semibold, size: 17)
    /// 강조 본문 — 작성자 이름, 리스트 행의 첫 줄
    static let subheadline = font(.body, .semibold, size: 15)
    /// 본문 — 캡션·댓글·안내. 14에서 15로: 한글 본문은 14가 빽빽하다
    static let body = font(.body, .regular, size: 15)
    /// 보조 본문 — 이전 `bodyText`. 새 화면은 `body`를 쓰고, 이건 옮겨 가는 동안만 남는다
    static let bodyText = font(.body, .regular, size: 14)
    /// 절 라벨("배치"·"공개 범위") · 리스트 행의 둘째 줄. caption보다 한 단 크고 medium
    static let label = font(.body, .medium, size: 13)
    static let caption = font(.body, .regular, size: 11)
    static let numeric = font(.latin, .medium, size: 15)
    static let chip = font(.body, .medium, size: 12)
    /// 버튼·강조 라벨 — 원본 스케일에 없어 `font(.body, .semibold, size: 15)` 인라인 호출이
    /// 3곳(촬영 시작·촬영 방식·권한 안내)에 반복되던 것을 승격
    static let buttonLabel = font(.body, .semibold, size: 15)
    /// 로고 — 라틴 전용 서체. 로그인은 크게, 피드 헤더는 작게 같은 자간으로
    static func logo(size: CGFloat) -> Font { font(.latin, .bold, size: size) }
    /// 로고에 거는 자간 비율(크기 × 이 값)
    static let logoKerning: CGFloat = 0.12
}

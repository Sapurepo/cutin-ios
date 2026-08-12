/* 탭 정의 — 명세 §4.2의 5탭. 가운데 항목은 화면이 아니라 **액션**(촬영 시트 열기)이라
 * `isAction`으로 구분한다. SwiftUI의 `Tab` 뷰와 이름이 겹치지 않도록 AppTab으로 둔다. */

enum AppTab: Hashable {
    case home
    case friends
    /// 중앙 강조 CTA — 선택되는 탭이 아니라 촬영 플로우를 여는 트리거
    case capture
    case profile
    case archive

    var title: String {
        switch self {
        case .home: return "홈"
        case .friends: return "친구"
        case .capture: return "촬영"
        case .profile: return "프로필"
        case .archive: return "보관"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .friends: return "person.2"
        case .capture: return "camera.fill"
        case .profile: return "person.crop.circle"
        case .archive: return "bookmark"
        }
    }

    /// 선택 시 탭을 바꾸지 않고 시트를 여는 항목
    var isAction: Bool { self == .capture }
}

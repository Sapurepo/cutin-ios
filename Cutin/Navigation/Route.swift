/* 탭 화면 안의 목적지. 촬영 시트 안의 단계(`CaptureStep`)와는 다른 축이라 따로 둔다.
 *
 * **모델이 아니라 id를 나른다.** 0.2.0에서 포스트가 원격 타입이 되어도 라우팅은 그대로다.
 * 값으로 나르면 푸시된 화면이 스냅샷을 들게 되고, 그 사이 목록에서 바뀐 것(보관·삭제)이
 * 상세 화면에 반영되지 않는다.
 *
 * 열거형으로 둔 이유는 `navigationDestination(for: UUID.self)`가 "어떤 UUID든 포스트 상세"라고
 * 선언해 버리기 때문이다 — 타인 프로필이 들어오면서 그 선언이 실제로 충돌하게 됐다. */

import Foundation

enum Route: Hashable {
    case postDetail(UUID)
    /// 타인 프로필(§9). 내 프로필은 탭이라 여기 오지 않는다.
    case userProfile(UUID)
    /// 댓글 목록(§7.2). 상세에서 푸시한다 — 시트로 띄우면 키보드와 겹쳐 목록이 반쪽이 된다.
    case comments(UUID)
    /// 인앱 알림(§10). 탭이 아니라 피드 툴바에서 푸시한다 — 5탭은 명세로 확정돼 있다.
    case notifications
    /// 알림 설정(§3.3 슬롯 · §8.3 설정). 프로필에서 푸시한다.
    case notificationSettings
    /// 서비스 팁 재열람(§3.5 "도움말에서 재열람"). 프로필 설정 메뉴에서 푸시한다.
    case tips
}

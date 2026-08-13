/* 탭 화면 안의 목적지. 촬영 시트 안의 단계(`CaptureStep`)와는 다른 축이라 따로 둔다.
 *
 * **모델이 아니라 id를 나른다.** 0.2.0에서 포스트가 원격 타입이 되어도 라우팅은 그대로다.
 * 값으로 나르면 푸시된 화면이 스냅샷을 들게 되고, 그 사이 목록에서 바뀐 것(보관·삭제)이
 * 상세 화면에 반영되지 않는다.
 *
 * 지금은 케이스가 하나다. 열거형으로 두는 이유는 `navigationDestination(for: UUID.self)`가
 * "어떤 UUID든 포스트 상세"라고 선언해 버리기 때문이다 — 다음 목적지(타인 프로필 등)가
 * 들어올 때 그 선언이 충돌한다. */

import Foundation

enum Route: Hashable {
    case postDetail(UUID)
}

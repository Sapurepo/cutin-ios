/* 햅틱 — 셋뿐이다. 화면마다 제너레이터를 만들면 세기가 제각각이 되고, 그러면 손끝이 앱을
 * 여러 사람이 만든 것처럼 느낀다.
 *   light   가벼운 확인 — 반응(+ SoundEffects.pop)·보관·인트로의 넷째 장
 *   medium  자리를 잡는 것 — 미리보기 팝업이 뜰 때, 셔터
 *   success 끝났다 — 발행 완료 (+ SoundEffects.success) */

import UIKit

// UIKit 제너레이터는 메인 액터다 — 부르는 곳도 전부 뷰(메인)라 여기서 못 박는다.
@MainActor
enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

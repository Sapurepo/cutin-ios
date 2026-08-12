/* 탭 선택과 촬영 시트를 한곳에서 소유한다.
 *
 * 이전에는 RootView가 `capturePath`를 직접 대입해 화면을 넘겼다(RootView.swift:31,49,54).
 * 촬영은 탭 전환이 아니라 "어느 탭에서든 열리는 모달 플로우"라 탭 트리 안에 두면
 * 중앙 CTA·draft 차단(§5.3)·저장 후 피드 복귀가 모두 뷰 안에 묶인다. */

import Observation

/// 촬영 시트 내부의 단계. 시트 밖 탭 화면의 라우팅과 섞이지 않게 분리해 둔다.
enum CaptureStep: Hashable {
    case camera
    case compose
}

@MainActor
@Observable
final class AppCoordinator {
    private(set) var tab: AppTab = .home
    var isCapturePresented = false
    var capturePath: [CaptureStep] = []

    /// 액션 탭(중앙 CTA)은 선택값으로 삼지 않는다 — 탭은 그대로 두고 시트만 연다.
    func select(_ tab: AppTab) {
        guard !tab.isAction else {
            startCapture()
            return
        }
        self.tab = tab
    }

    func startCapture() {
        capturePath = []
        isCapturePresented = true
    }

    func advanceCapture(to step: CaptureStep) {
        capturePath.append(step)
    }

    /// 저장 완료 — 시트를 닫고 결과가 보이는 홈으로 돌려보낸다.
    func finishCapture() {
        isCapturePresented = false
        capturePath = []
        tab = .home
    }
}

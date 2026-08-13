/* 탭 선택과 촬영 시트를 한곳에서 소유한다.
 *
 * 이전에는 RootView가 `capturePath`를 직접 대입해 화면을 넘겼다(RootView.swift:31,49,54).
 * 촬영은 탭 전환이 아니라 "어느 탭에서든 열리는 모달 플로우"라 탭 트리 안에 두면
 * 중앙 CTA·draft 차단(§5.3)·저장 후 피드 복귀가 모두 뷰 안에 묶인다. */

import Observation

/// 촬영 시트 내부의 단계. 시트 밖 탭 화면의 라우팅과 섞이지 않게 분리해 둔다.
/// 루트(컷 수·방식 선택)는 값이 없다 — 경로가 빈 상태가 곧 루트다.
enum CaptureStep: Hashable {
    case camera
    /// 편집 3단계 — 명세 §6.1 / §6.2 / §6.4
    case template
    case filter
    case finish
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

    /// 같은 단계를 두 번 밀지 않는다 — 애니메이션이 끝나기 전 연타하면 CaptureView가 둘 쌓이고
    /// 각자 AVCaptureSession을 시작해 카메라를 다툰다. 이전 구현이 경로를 통째로 대입해
    /// 우연히 멱등이었던 성질을 여기서 명시적으로 지킨다.
    func advanceCapture(to step: CaptureStep) {
        guard capturePath.last != step else { return }
        capturePath.append(step)
    }

    /// 저장 완료 — 커버를 닫고 결과가 보이는 홈으로 돌려보낸다.
    /// 경로는 비우지 않는다. 닫히는 프레임에 NavigationStack을 루트로 되돌리라고 시키면
    /// 전환이 튀고, 다음 `startCapture()`가 어차피 초기화한다.
    func finishCapture() {
        isCapturePresented = false
        tab = .home
    }
}

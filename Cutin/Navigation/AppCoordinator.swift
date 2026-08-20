/* 탭 선택과 촬영 시트를 한곳에서 소유한다.
 *
 * 이전에는 RootView가 `capturePath`를 직접 대입해 화면을 넘겼다(RootView.swift:31,49,54).
 * 촬영은 탭 전환이 아니라 "어느 탭에서든 열리는 모달 플로우"라 탭 트리 안에 두면
 * 중앙 CTA·draft 차단(§5.3)·저장 후 피드 복귀가 모두 뷰 안에 묶인다. */

import Foundation
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

    /* 포스트 미리보기(길게 누르기 → 팝업). 탭 트리 **위**에 그려야 탭바·내비게이션 바까지 스크림이
     * 덮이므로 셸이 소유한다 — 프로필 그리드가 요청하고 `RootView`가 그린다. */
    var peekPostId: UUID?

    /* 탭 넷의 네비게이션 경로. 화면 밖(미리보기 팝업)에서 상세를 밀어 넣으려면 "지금 보고 있는
     * 스택"에 손이 닿아야 한다 — NavigationLink는 자기 스택 안에서만 통한다. */
    var homePath: [Route] = []
    var friendsPath: [Route] = []
    var profilePath: [Route] = []
    var archivePath: [Route] = []

    /// 지금 보고 있는 탭의 스택에 밀어 넣는다. 촬영 탭은 스택이 없다 — 홈으로 보낸다.
    func push(_ route: Route) {
        switch tab {
        case .home: homePath.append(route)
        case .friends: friendsPath.append(route)
        case .profile: profilePath.append(route)
        case .archive: archivePath.append(route)
        case .capture: tab = .home; homePath.append(route)
        }
    }

    /// 액션 탭(중앙 CTA)은 선택값으로 삼지 않는다 — 탭은 그대로 두고 시트만 연다.
    ///
    /// `hasDraft`를 인자로 받는 이유: draft가 있는지는 촬영 플로우가 알고, 코디네이터는
    /// 그 결정을 화면으로 옮기는 일만 한다. 코디네이터가 플로우를 직접 들면 셸이 촬영 상태를
    /// 소유하게 되고, 그건 앱 수명 상태를 셸에서 뺐던 이유와 반대 방향이다.
    func select(_ tab: AppTab, hasDraft: Bool) {
        guard !tab.isAction else {
            requestCapture(hasDraft: hasDraft)
            return
        }
        self.tab = tab
    }

    /// 미완료 촬영이 있으면 새 촬영을 열지 않고 차단 시트를 띄운다 (§5.3).
    func requestCapture(hasDraft: Bool) {
        if hasDraft {
            isDraftBlockPresented = true
        } else {
            startCapture()
        }
    }

    var isDraftBlockPresented = false

    /* 이어 쓰는 촬영은 **설정 화면을 루트로 두지 않는다.**
     *
     * 처음에는 경로에 `.camera`를 밀어 넣어 "뒤로 가면 재촬영 화면"이 되게 했는데, 그것으로는
     * 막히지 않았다. 카메라 화면의 X는 커버를 닫는 게 아니라 스택을 pop해서 촬영 설정에
     * 착륙하고(스와이프 뒤로도 같다), 거기서 `촬영 시작`을 누르면 `configure`가 이어 쓰던
     * draft를 확인도 없이 지운다 — §5.3이 차단 시트로 막으려던 바로 그 일이다.
     *
     * 그래서 설정 화면 자체를 스택에서 뺀다. 이어 쓰는 동안 컷 수·방식은 이미 정해져 있으므로
     * 설정 화면은 의미도 없다. */
    private(set) var isResumingDraft = false

    func startCapture() {
        isResumingDraft = false
        capturePath = []
        isCapturePresented = true
    }

    /// draft를 이어서 쓴다. 카메라가 루트가 되고, 컷이 다 찼으면 편집 첫 단계를 그 위에 올린다.
    func resumeCapture(isComplete: Bool) {
        isResumingDraft = true
        capturePath = isComplete ? [.template] : []
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

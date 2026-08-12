/* 저장소·촬영 상태는 앱 수명과 같다 — 탭 셸(RootView)이 소유하면 셸을 다시 그리는 순간
 * 진행 중인 촬영이 사라질 수 있어 여기서 만들어 환경으로 내린다. */

import SwiftUI

@main
struct CutinApp: App {
    @State private var store = FeedStore()
    @State private var flow = CaptureFlow()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(flow)
        }
    }
}

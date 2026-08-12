/* 저장된 포스트와 진행 중인 촬영은 화면이 아니라 앱이 가진 상태라 여기서 만들어 환경으로 내린다.
 * 어느 탭에서든 읽고, 탭을 넘나들어도 같은 값이어야 한다.
 *
 * 촬영 화면이 떠 있는지(`AppCoordinator`)는 셸의 관심사라 RootView에 남겨 뒀다. 그래서 셸이
 * 다시 만들어지면 촬영 커버는 닫힌다 — 그때 컷을 잃지 않는 건 draft 영속(§5.3)의 일이다. */

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

/* 탭 셸 — iOS 26의 TabView는 별도 래퍼 없이 Liquid Glass 탭바를 준다.
 * RN판은 `@callstack/liquid-glass`로 감싼 커스텀 NavBar(`components/navBar.tsx`)가 필요했다.
 *
 * 스파이크 범위상 5탭(명세 §4.2)을 다 만들지 않고 피드·촬영 2탭만 둔다. */

import SwiftUI

struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var store = FeedStore()
    @State private var flow = CaptureFlow()
    @State private var tab: AppTab = .feed
    @State private var capturePath: [CaptureStep] = []

    /// SwiftUI의 `Tab` 뷰와 이름이 겹치지 않도록 AppTab으로 둔다.
    enum AppTab: Hashable { case feed, capture }
    enum CaptureStep: Hashable { case camera, compose }

    var body: some View {
        TabView(selection: $tab) {
            Tab("피드", systemImage: "square.grid.2x2", value: AppTab.feed) {
                NavigationStack {
                    FeedView()
                }
            }

            Tab("촬영", systemImage: "camera", value: AppTab.capture) {
                NavigationStack(path: $capturePath) {
                    CaptureSetupView(flow: flow) {
                        capturePath = [.camera]
                    }
                    .navigationDestination(for: CaptureStep.self) { step in
                        destination(step)
                    }
                }
            }
        }
        .environment(store)
        .environment(\.palette, Palette.of(colorScheme))
        .tint(Palette.of(colorScheme).accent)
    }

    @ViewBuilder
    private func destination(_ step: CaptureStep) -> some View {
        switch step {
        case .camera:
            CaptureView(flow: flow) {
                capturePath = [.camera, .compose]
            }
        case .compose:
            ComposeView(cuts: flow.cuts, count: flow.count) {
                flow.reset()
                capturePath = []
                tab = .feed
            }
        }
    }
}

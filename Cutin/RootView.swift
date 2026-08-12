/* 탭 셸 — iOS 26의 TabView는 별도 래퍼 없이 Liquid Glass 탭바를 준다.
 * RN판은 `@callstack/liquid-glass`로 감싼 커스텀 NavBar(`components/navBar.tsx`)가 필요했다.
 *
 * 중앙 CTA(명세 §4.2-3)는 "선택되지 않는 탭"이다. TabView의 selection 바인딩 setter에서
 * 액션 탭을 가로채 탭 값은 그대로 두고 촬영 플로우만 띄운다 — 커스텀 탭바를 손으로 그리면
 * Liquid Glass 탭바를 잃기 때문에 이 방식을 택했다. */

import SwiftUI

struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CaptureFlow.self) private var flow

    @State private var coordinator = AppCoordinator()

    var body: some View {
        TabView(selection: tabSelection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                NavigationStack { FeedView() }
            }

            Tab(AppTab.friends.title, systemImage: AppTab.friends.systemImage, value: AppTab.friends) {
                NavigationStack { FriendsView() }
            }

            /// 내용이 표시되는 일은 없다 — selection이 이 값이 되기 전에 가로채인다.
            Tab(AppTab.capture.title, systemImage: AppTab.capture.systemImage, value: AppTab.capture) {
                Color.clear
            }

            Tab(AppTab.profile.title, systemImage: AppTab.profile.systemImage, value: AppTab.profile) {
                NavigationStack { ProfileView() }
            }

            Tab(AppTab.archive.title, systemImage: AppTab.archive.systemImage, value: AppTab.archive) {
                NavigationStack { ArchiveView() }
            }
        }
        .fullScreenCover(isPresented: $coordinator.isCapturePresented) {
            captureFlow
        }
        .environment(\.palette, Palette.of(colorScheme))
        .tint(Palette.of(colorScheme).accent)
    }

    /// 액션 탭을 선택값으로 삼지 않는 커스텀 바인딩.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { coordinator.tab },
            set: { coordinator.select($0) }
        )
    }

    // MARK: - 촬영 플로우

    /* 시트가 아니라 fullScreenCover인 이유: 촬영 화면은 뷰파인더·썸네일·셔터가 화면 높이를
     * 나눠 쓰는 고정 레이아웃이고, page sheet에서는 burst 카운트다운 중 아래로 끌어
     * 실수로 닫히는 경로가 생긴다. */
    private var captureFlow: some View {
        NavigationStack(path: $coordinator.capturePath) {
            CaptureSetupView(flow: flow) {
                coordinator.advanceCapture(to: .camera)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { coordinator.isCapturePresented = false }
                }
            }
            .navigationDestination(for: CaptureStep.self) { step in
                destination(step)
            }
        }
    }

    @ViewBuilder
    private func destination(_ step: CaptureStep) -> some View {
        switch step {
        case .camera:
            CaptureView(flow: flow) {
                coordinator.advanceCapture(to: .compose)
            }
        case .compose:
            ComposeView(cuts: flow.cuts, count: flow.count) {
                flow.reset()
                coordinator.finishCapture()
            }
        }
    }
}

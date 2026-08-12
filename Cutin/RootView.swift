/* 탭 셸 — iOS 26의 TabView는 별도 래퍼 없이 Liquid Glass 탭바를 준다.
 * RN판은 `@callstack/liquid-glass`로 감싼 커스텀 NavBar(`components/navBar.tsx`)가 필요했다.
 *
 * 중앙 CTA(명세 §4.2-3)는 "선택되지 않는 탭"이다. TabView의 selection 바인딩 setter에서
 * 액션 탭을 가로채 탭 값은 그대로 두고 촬영 플로우만 띄운다 — 커스텀 탭바를 손으로 그리면
 * Liquid Glass 탭바를 잃기 때문에 이 방식을 택했다.
 *
 * ⚠️ 거부된 선택은 바인딩 값을 바꾸지 않으므로 SwiftUI에 되돌릴 변화가 없다. TabView는
 * UIKit 기반이라 탭바 하이라이트가 촬영에 남는 기기가 있을 수 있다 — 실기기에서 확인할 항목.
 * 그 경우 `captureTabFallback`이 사용자를 빈 화면에 갇히지 않게 받아주고, 하이라이트까지
 * 문제가 되면 4탭 + `tabViewBottomAccessory`로 바꾼다. */

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

            Tab(AppTab.capture.title, systemImage: AppTab.capture.systemImage, value: AppTab.capture) {
                captureTabFallback
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

    /* 정상 경로에서는 보이지 않는다 — selection이 `.capture`가 되기 전에 가로채이기 때문.
     * 그래도 빈 화면을 두지 않는 이유: 가로채기가 탭바 하이라이트를 되돌리지 못하는 경우
     * 사용자가 아무것도 없는 화면에 남는다. 이 자리를 살아 있는 진입점으로 둔다. */
    private var captureTabFallback: some View {
        EmptyStateView(
            title: "컷을 남겨요",
            message: "아래 버튼으로 촬영을 시작하세요",
            systemImage: AppTab.capture.systemImage
        ) {
            Button("촬영 시작") { coordinator.startCapture() }
                .primaryGlassButton(tint: Palette.of(colorScheme).accent)
        }
        .background(Palette.of(colorScheme).bg)
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
                    /* flow는 앱 수명이라 여기서 비우지 않으면 찍은 컷(원본 해상도 UIImage)이
                     * 프로세스가 죽을 때까지 남고, 어느 화면에서도 닿을 수 없다.
                     * 이탈한 컷을 draft로 보존하는 정책(§5.3)은 draft 브랜치에서 이 자리를 대체한다. */
                    Button("닫기") {
                        flow.reset()
                        coordinator.isCapturePresented = false
                    }
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

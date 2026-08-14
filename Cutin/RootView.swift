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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CaptureFlow.self) private var flow
    @Environment(TemplateCatalog.self) private var catalog
    @Environment(PushRegistrar.self) private var push

    @State private var coordinator = AppCoordinator()
    @State private var pendingIntent: CaptureIntent?

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
        /* 촬영 커버는 시트가 **완전히 닫힌 뒤** 연다. 같은 갱신에서 시트를 닫고 커버를 열면
         * 아직 사라지는 중인 모달 위에 새 모달을 올리라고 시키는 셈이라 커버가 조용히 안 뜨고,
         * 그 사이 draft는 이미 지워져 사용자가 아무것도 없는 탭 화면에 남는다. */
        .sheet(isPresented: $coordinator.isDraftBlockPresented, onDismiss: runPendingIntent) {
            draftBlock
        }
        .environment(\.palette, Palette.of(colorScheme))
        .tint(Palette.of(colorScheme).accent)
        /* 템플릿 목록을 로그인 뒤 **미리** 받는다(`/templates`·`/frames`가 auth 필요).
         * 촬영 설정 화면도 스스로 부르지만, 그때 받기 시작하면 촬영을 열자마자 로딩을 본다.
         * 이어쓰기 경로는 설정 화면을 건너뛰므로 여기서 받아 두지 않으면 편집 1단계의
         * 배치·프레임 칩이 빈 줄로 뜬다. */
        .task { await catalog.loadIfNeeded() }
        /* 이미 알림을 허용한 사용자의 APNs 등록. 토큰은 재설치·복원에서 바뀌므로 로그인한
         * 셸이 뜰 때마다 다시 등록한다 — `PushRegistrar.registerIfAuthorized`가 이 호출
         * 하나로 배선된다(권한이 없으면 아무 일도 하지 않는다). */
        .task { await push.registerIfAuthorized() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                /* 만료는 읽는 시점 판정이지만(§5.3) 이 객체는 앱 수명이라 시작 시 한 번만으로는
                 * 며칠 켜 둔 기기에서 지난 draft를 계속 내놓는다. 돌아올 때 다시 읽는다. */
                flow.refreshDraft()
            } else {
                /* 떠나기 직전에 draft 메타를 내린다 — 마지막 컷 이후에 고른 템플릿·보정·캡션이
                 * 여기서 파일로 남는다. 강제 종료도 백그라운드를 지나므로 마지막 기회다. */
                flow.persistDraftMeta()
            }
        }
    }

    /// 액션 탭을 선택값으로 삼지 않는 커스텀 바인딩.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { coordinator.tab },
            set: { coordinator.select($0, hasDraft: flow.hasDraft) }
        )
    }

    // MARK: - 미완료 촬영 차단 (§5.3)

    /// 시트가 닫힌 **뒤에** 할 일. 시트 안에서 draft를 지우면 시트 내용이 사라져 빈 상자가 남는다.
    private enum CaptureIntent { case fresh, resume }

    @ViewBuilder
    private var draftBlock: some View {
        if let draft = flow.draft {
            DraftBlockSheet(
                draft: draft,
                loadThumbnail: { await flow.draftThumbnail(maxPixel: 160) },
                onResume: { close(with: .resume) },
                onDiscard: { close(with: .fresh) }
            )
            .environment(\.palette, Palette.of(colorScheme))
        }
    }

    private func close(with intent: CaptureIntent) {
        pendingIntent = intent
        coordinator.isDraftBlockPresented = false
    }

    private func runPendingIntent() {
        guard let intent = pendingIntent else { return }
        pendingIntent = nil

        switch intent {
        case .fresh:
            flow.discardDraft()
            coordinator.startCapture()

        case .resume:
            Task {
                guard await flow.resumeDraft() else {
                    /* 되살리지 못했다(컷 파일이 사라졌거나 디코드가 깨졌다). 이 시점에 draft는
                     * 정리돼 있다. 카메라로 바로 보내면 `configure`를 건너뛰어 사용자가 고르지도
                     * 않은 컷 수·방식(메모리에 남아 있던 값)으로 새 촬영이 시작된다 — 설정부터 연다. */
                    coordinator.startCapture()
                    return
                }
                coordinator.resumeCapture(isComplete: flow.isComplete)
            }
        }
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
            Button("촬영 시작") { coordinator.requestCapture(hasDraft: flow.hasDraft) }
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
            Group {
                if coordinator.isResumingDraft {
                    // 이어 쓰는 촬영에는 설정 화면이 없다 — AppCoordinator.isResumingDraft 주석 참조.
                    cameraStep
                } else {
                    CaptureSetupView(flow: flow) {
                        coordinator.advanceCapture(to: .camera)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            /* 메모리만 비운다. flow는 앱 수명이라 비우지 않으면 찍은 컷(원본 해상도
                             * UIImage)이 프로세스가 죽을 때까지 남는다. 파일로 내려간 draft는 그대로
                             * 두는 것이 §5.3이다 — 다음 진입에서 차단 시트로 이어 쓴다. */
                            Button("닫기") {
                                flow.clearMemory()
                                coordinator.isCapturePresented = false
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: CaptureStep.self) { step in
                destination(step)
            }
        }
    }

    private var cameraStep: some View {
        CaptureView(flow: flow) {
            coordinator.advanceCapture(to: .template)
        }
    }

    @ViewBuilder
    private func destination(_ step: CaptureStep) -> some View {
        switch step {
        case .camera:
            cameraStep
        case .template:
            TemplateStepView(flow: flow) {
                coordinator.advanceCapture(to: .filter)
            }
        case .filter:
            FilterStepView(flow: flow) {
                coordinator.advanceCapture(to: .finish)
            }
        case .finish:
            FinishStepView(flow: flow) {
                // draft 해제는 commit이 이미 했다 — 여기서는 메모리만 비운다.
                flow.clearMemory()
                coordinator.finishCapture()
            }
        }
    }
}

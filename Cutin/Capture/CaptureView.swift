/* 촬영 화면 — `apps/mobile/src/app/capture/camera.tsx`(298행)의 UX를 그대로 옮긴다.
 * burst 3-2-1 카운트다운 · 재촬영 · 권한 거부 폴백까지 동일하게 두어야 나란히 비교할 수 있다.
 * 촬영 화면은 항상 다크(잉크) 캔버스. */

import SwiftUI

struct CaptureView: View {
    @Bindable var flow: CaptureFlow
    let onComplete: () -> Void

    @State private var camera = CameraController()
    @Environment(\.dismiss) private var dismiss

    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var isShooting = false
    @State private var failure: CameraController.CaptureError?

    private let ink = Palette.dark

    var body: some View {
        VStack(spacing: 0) {
            topBar
            viewfinder
            thumbnails
            shutterRow
        }
        .background(ink.bg)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear { camera.start() }
        .onDisappear {
            countdownTask?.cancel()
            camera.stop()
        }
        /* "컷이 채워졌을 때"만 넘긴다. `isComplete`만 보면 재촬영 **취소**에도 넘어간다 —
         * 컷이 다 찬 상태에서 썸네일을 눌러 재촬영을 걸면 isComplete가 false가 되고,
         * 같은 썸네일을 다시 눌러 취소하면(toggleRetake가 지원하는 동작) 사진 한 장 찍지 않고
         * true로 되돌아가 편집으로 밀려간다. */
        .onChange(of: flow.cutsRevision) { _, _ in
            if flow.isComplete { onComplete() }
        }
    }

    // MARK: - 상단

    private var topBar: some View {
        HStack {
            iconButton("xmark") {
                countdownTask?.cancel()
                dismiss()
            }
            Spacer()
            ProgressDots(total: flow.count.rawValue, current: flow.cuts.count)
                .padding(.horizontal, Spacing.x3)
                .padding(.vertical, Spacing.x1)
                .glassEffect(.regular, in: .capsule)
            Spacer()
            iconButton("arrow.trianglehead.2.clockwise.rotate.90.camera") {
                camera.toggleFacing()
            }
        }
        .padding(.horizontal, Spacing.x3)
        .padding(.vertical, Spacing.x3)
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: Layout.tapTarget, height: Layout.tapTarget)
        }
    }

    // MARK: - 뷰파인더

    private var viewfinder: some View {
        ZStack {
            switch camera.permission {
            case .granted where camera.isUnavailable:
                unavailableBox

            case .granted:
                CameraPreview(session: camera.session)
                    .ignoresSafeArea(edges: .horizontal)

                if let countdown {
                    ZStack {
                        // 0x0A0A0B@0.25였다 — 잉크 배경과 같은 값이라 토큰으로 바꾼다.
                        ink.bg.opacity(0.25)
                        Text("\(countdown)")
                            .font(Typography.font(.latin, .semibold, size: 96))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .allowsHitTesting(false)
                }

                VStack {
                    Spacer()
                    if let failure {
                        failureLabel(failure)
                    }
                    Text(counterLabel)
                        .font(flow.retakeIndex != nil
                              ? Typography.font(.body, .medium, size: 15)
                              : Typography.font(.latin, .regular, size: 15))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, Spacing.x3)
                        .padding(.vertical, Spacing.x1)
                        .glassEffect(.clear, in: .capsule)
                        .padding(.bottom, Spacing.x3)
                }

            case .needsRequest, .denied:
                permissionBox
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ink.surface)
        .clipShape(.rect(cornerRadius: Radius.lg))
        .padding(.horizontal, Spacing.x3)
    }

    private var counterLabel: String {
        if let index = flow.retakeIndex {
            return "\(index + 1)번째 컷 다시 찍기"
        }
        return "\(flow.nextSlot) / \(flow.count.rawValue)"
    }

    /* 촬영 실패를 조용히 넘기면 사용자는 셔터가 고장 난 줄 안다 — 이전 구현은 `try?`로 삼켰다.
     *
     * 마무리 화면의 저장 실패 문구와 공용 배너로 묶는 것은 검토했다가 접었다 — 이쪽은 뷰파인더
     * 위에 얹는 캡슐(강제 다크)이고 그쪽은 폼 안의 캡션 줄(테마 팔레트)이라, 하나로 묶으면
     * 스타일 변형 파라미터가 붙는다. 네트워크 문구가 들어오는 0.2.0에 다시 볼 지점이다. */
    private func failureLabel(_ error: CameraController.CaptureError) -> some View {
        Text(message(for: error))
            .font(Typography.chip)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.x3)
            .padding(.vertical, Spacing.x2)
            .background(ink.danger.opacity(0.9), in: .capsule)
            .padding(.bottom, Spacing.x2)
    }

    private func message(for error: CameraController.CaptureError) -> String {
        switch error {
        case .notReady: return "카메라가 준비되지 않았어요. 잠시 후 다시 눌러주세요"
        case .busy: return "이전 컷을 저장하는 중이에요"
        case .interrupted: return "촬영이 중단됐어요. 카메라가 돌아오면 이어서 찍을 수 있어요"
        // .cancelled는 사용자가 접은 경우라 이 함수까지 오지 않는다(shoot에서 걸러진다).
        case .noImageData, .timedOut, .cancelled: return "촬영에 실패했어요. 다시 눌러주세요"
        }
    }

    /* 권한은 있는데 카메라를 열지 못한 상태 — 다른 앱이 카메라를 쥐고 있으면(FaceTime·연속성
     * 카메라) 입력을 붙일 수 없다. 검은 프리뷰만 두면 사용자는 앱이 고장 난 줄 알고, 실제로
     * 되살릴 방법도 앱을 껐다 켜는 것뿐이었다. */
    private var unavailableBox: some View {
        VStack(spacing: Spacing.x4) {
            Text("카메라를 열 수 없어요")
                .font(Typography.buttonLabel)
                .foregroundStyle(.white)
            Text("다른 앱이 카메라를 쓰고 있는지 확인해 주세요")
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button("다시 시도") { camera.start() }
                .primaryGlassButton(tint: .white)
        }
        .padding(Spacing.x6)
        .tint(.white)
    }

    private var permissionBox: some View {
        VStack(spacing: Spacing.x4) {
            Text("컷 촬영을 위해\n카메라 권한이 필요해요")
                .font(Typography.buttonLabel)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            if camera.permission == .denied {
                // iOS는 한 번 거부된 뒤 앱이 다시 묻는 것을 허용하지 않는다.
                Button("설정에서 허용") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.glass)
            } else {
                Button("카메라 권한 허용") { camera.start() }
                    .primaryGlassButton(tint: .white)
            }
        }
        .padding(Spacing.x6)
        .tint(.white)
    }

    // MARK: - 썸네일 스트립

    private var thumbnails: some View {
        HStack(spacing: Spacing.x1) {
            ForEach(0..<flow.count.rawValue, id: \.self) { index in
                let filled = index < flow.cuts.count
                let isRetake = flow.retakeIndex == index
                let isNext = !filled && index == flow.cuts.count && flow.retakeIndex == nil

                Button {
                    flow.toggleRetake(index)
                } label: {
                    ZStack {
                        // 0x232327 = 잉크 팔레트의 border와 같은 값이었다.
                        ink.border
                        if filled {
                            Image(uiImage: flow.cuts[index])
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 8))
                    .tokenBorder(RoundedRectangle(cornerRadius: 8),
                                 color: isRetake || isNext ? Color.white : ink.borderStrong,
                                 lineWidth: isRetake ? 2 : (isNext ? 1.5 : 1))
                }
                .buttonStyle(.plain)
                .disabled(!filled)
                .accessibilityLabel("\(index + 1)번째 컷 재촬영")
            }
        }
        .padding(Spacing.x3)
    }

    // MARK: - 셔터

    /// 눌러도 되는 조건을 한 곳에 둔다 — 이전 구현은 `disabled`에는 `isShooting`이 있고
    /// `opacity`에는 없어서 촬영 중에 눌리지 않는 셔터가 멀쩡해 보였다.
    /// `isRunning`까지 봐야 한다: 인터럽션으로 세션이 내려가면 프리뷰는 검은데 셔터만 멀쩡해
    /// 보이고, 누를 때마다 실패 문구가 뜬다.
    private var canShoot: Bool {
        camera.permission == .granted && camera.isRunning && countdown == nil && !isShooting
            && hasSlot
    }

    /// 채울 자리가 없으면 셔터를 막는다. `addCut`은 컷이 다 찬 상태에서 조용히 버리므로,
    /// 이 검사가 없으면 사진을 찍고 아무 일도 일어나지 않는다 — draft를 이어 쓰면 컷이
    /// 다 찬 채로 카메라 화면에 서 있는 상태가 정상 경로가 된다(§5.3).
    private var hasSlot: Bool {
        flow.retakeIndex != nil || flow.cuts.count < flow.count.rawValue
    }

    private var shutterRow: some View {
        Button(action: onShutter) {
            Circle()
                .fill(.white)
                .frame(width: 72, height: 72)
                .overlay {
                    Circle().stroke(.white.opacity(0.35), lineWidth: 4)
                }
        }
        .buttonStyle(.plain)
        .disabled(!canShoot)
        .opacity(canShoot ? 1 : 0.4)
        .accessibilityLabel("촬영")
        .padding(.top, Spacing.x2)
        .padding(.bottom, Spacing.x8)
    }

    // MARK: - 촬영 동작

    private func onShutter() {
        guard canShoot else { return }
        failure = nil

        if flow.mode == .burst, flow.retakeIndex == nil {
            countdownTask = Task { await runBurst() }
        } else {
            Task { await shoot() }
        }
    }

    /// burst: 3-2-1 카운트다운 → 촬영, 남은 컷이 있으면 반복.
    private func runBurst() async {
        while !Task.isCancelled, flow.cuts.count < flow.count.rawValue {
            for tick in stride(from: 3, through: 1, by: -1) {
                if Task.isCancelled { break }
                withAnimation { countdown = tick }
                try? await Task.sleep(for: .seconds(1))
            }
            if Task.isCancelled { break }
            countdown = nil

            // 실패하면 멈춘다. 이전 구현은 실패를 삼키고 루프를 계속 돌아, 카메라가 못 찍는
            // 상황에서 컷 수가 늘지 않는 카운트다운을 영원히 반복했다.
            guard await shoot() else { break }
        }
        countdown = nil
    }

    @discardableResult
    private func shoot() async -> Bool {
        guard !isShooting else { return false }
        isShooting = true
        defer { isShooting = false }

        do {
            flow.addCut(try await camera.capturePhoto())
            return true
        } catch CameraController.CaptureError.cancelled {
            // 화면을 벗어났거나 전/후면을 바꿨다 — 사용자에게 알릴 실패가 아니다.
            return false
        } catch {
            failure = error as? CameraController.CaptureError ?? .noImageData
            return false
        }
    }
}

/// 진행 도트 — 원본 `components/progressDots.tsx`
private struct ProgressDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: Spacing.x1) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < current ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

/* 촬영 화면 — `apps/mobile/src/app/capture/camera.tsx`(298행)의 UX를 그대로 옮긴다.
 * burst 3-2-1 카운트다운 · 재촬영 · 권한 거부 폴백까지 동일하게 두어야 나란히 비교할 수 있다.
 * 촬영 화면은 항상 다크(잉크) 캔버스. */

import SwiftUI

struct CaptureView: View {
    @Bindable var flow: CaptureFlow
    let onComplete: () -> Void

    @StateObject private var camera = CameraController()
    @Environment(\.dismiss) private var dismiss

    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var isShooting = false

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
        .onChange(of: flow.isComplete) { _, complete in
            if complete { onComplete() }
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
            case .granted:
                CameraPreview(session: camera.session)
                    .ignoresSafeArea(edges: .horizontal)

                if let countdown {
                    ZStack {
                        Color(hex: 0x0A0A0B, alpha: 0.25)
                        Text("\(countdown)")
                            .font(Typography.font(.latin, .semibold, size: 96))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .allowsHitTesting(false)
                }

                VStack {
                    Spacer()
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

            case .unknown, .denied:
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

    private var permissionBox: some View {
        VStack(spacing: Spacing.x4) {
            Text("컷 촬영을 위해\n카메라 권한이 필요해요")
                .font(Typography.buttonLabel)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            if case .denied(let canAskAgain) = camera.permission, !canAskAgain {
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
                        Color(hex: 0x232327)
                        if filled {
                            Image(uiImage: flow.cuts[index])
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 8))
                    .tokenBorder(RoundedRectangle(cornerRadius: 8),
                                 color: isRetake || isNext ? Color.white : Color(hex: 0x2C2C30),
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
        .disabled(camera.permission != .granted || countdown != nil || isShooting)
        .opacity(camera.permission != .granted || countdown != nil ? 0.4 : 1)
        .accessibilityLabel("촬영")
        .padding(.top, Spacing.x2)
        .padding(.bottom, Spacing.x8)
    }

    // MARK: - 촬영 동작

    private func onShutter() {
        guard countdown == nil else { return }
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
            await shoot()
        }
        countdown = nil
    }

    private func shoot() async {
        guard !isShooting else { return }
        isShooting = true
        defer { isShooting = false }

        if let image = try? await camera.capturePhoto() {
            flow.addCut(image)
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

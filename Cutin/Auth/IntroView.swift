/* 인트로 — 앱을 켤 때 네 컷이 한 칸씩 찍히고 CUTIN이 올라온다.
 *
 * **기다리는 시간을 새로 만들지 않는다.** 앱 시작 직후 `/users/me` 왕복(`AuthSession.restore`)이
 * 어차피 0.3~0.8초 걸리고, 0.3.0은 그동안 빈 배경이었다. 이 화면은 그 구간을 덮는 덮개다 —
 * 최소 0.9초(연출이 끝까지), 최대 1초(서버가 늦어도 더 붙잡지 않는다). 콜드 스타트에만 뜬다:
 * `AuthGate`가 앱 수명 동안 한 번 만들어지고 `restore()`도 한 번이라 백그라운드에서 돌아올 때는
 * 지나가지 않는다.
 *
 * 리듬은 제품에서 왔다 — 연속 촬영 3·2·1처럼 120ms 간격으로 한 칸씩, 칸마다 짧은 플래시.
 * 넷째 칸만 웜 포인트(켜진 것의 색)이고 그 순간 가벼운 햅틱 한 번. 이어서 워드마크가 넓게
 * 벌어진 자간에서 로고 자간으로 조여들며 올라온다.
 *
 * 움직임 줄이기가 켜져 있으면 완성된 그림을 0.4초 보여주고 끝난다. */

import SwiftUI

struct IntroView: View {
    /// 연출이 끝났다 — `AuthGate`가 이 뒤에 다음 화면으로 넘어간다.
    let onFinished: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var started = false

    /// 칸 간격(초). 넷째 칸이 0.36초에 찍히고 워드마크는 0.42초에 올라오기 시작한다.
    private static let beat: Double = 0.12
    private static let cutSize: CGFloat = 44
    private static let total: Double = 0.95

    var body: some View {
        VStack(spacing: Spacing.x6) {
            grid
            wordmark
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bg)
        .accessibilityLabel("CUTIN")
        .task {
            started = true
            let hold = reduceMotion ? 0.4 : Self.total
            try? await Task.sleep(for: .seconds(hold))
            onFinished()
        }
    }

    // MARK: - 네 컷

    // Lazy 그리드는 스크롤 없는 자리에서 셀 하나만 놓았다 — 넷은 손으로 놓는다.
    private var grid: some View {
        VStack(spacing: Spacing.x2) {
            HStack(spacing: Spacing.x2) { cut(0); cut(1) }
            HStack(spacing: Spacing.x2) { cut(2); cut(3) }
        }
    }

    /* 칸 하나 — 살짝 작았다가 자리를 잡고(0.86→1), 나타나는 순간 흰 플래시가 스치고 사라진다.
     * `keyframeAnimator`로 칸마다 시작 시각을 늦춘다 — 앞의 `hold` 구간이 그 지연이다. */
    private func cut(_ index: Int) -> some View {
        let isLast = index == 3
        let delay = reduceMotion ? 0 : Self.beat * Double(index) + 0.05
        return RoundedRectangle(cornerRadius: Radius.sm)
            .fill(isLast ? palette.brand : palette.textPrimary)
            .frame(width: Self.cutSize, height: Self.cutSize)
            .keyframeAnimator(initialValue: CutState(scale: reduceMotion ? 1 : 0.86,
                                                     opacity: reduceMotion ? 1 : 0,
                                                     flash: 0),
                              trigger: started) { view, state in
                view
                    .scaleEffect(state.scale)
                    .opacity(state.opacity)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(.white)
                            .opacity(state.flash)
                    }
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: delay)
                    LinearKeyframe(1, duration: 0.06)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.86, duration: delay)
                    SpringKeyframe(1.0, duration: 0.32, spring: .bouncy(duration: 0.32, extraBounce: 0.05))
                }
                KeyframeTrack(\.flash) {
                    LinearKeyframe(0, duration: delay)
                    LinearKeyframe(0.85, duration: 0.03)
                    LinearKeyframe(0, duration: 0.18)
                }
            }
            .onChange(of: started) { _, _ in
                // 넷째 컷의 셔터 — 그 시각에 맞춰 한 번.
                guard isLast, !reduceMotion else { return }
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
    }

    private struct CutState {
        var scale: CGFloat
        var opacity: Double
        var flash: Double
    }

    // MARK: - 워드마크

    private var wordmark: some View {
        let delay = reduceMotion ? 0 : Self.beat * 3 + 0.11
        let ink = palette.textPrimary   // 애니메이터 클로저는 비격리라 환경을 밖에서 읽어 둔다
        // 자간은 Text에만 걸리므로 글자를 애니메이터 안에서 그린다 — 밖의 자리만 고정해 둔다.
        return Color.clear
            .frame(width: 160, height: 36)
            .keyframeAnimator(initialValue: MarkState(kerning: reduceMotion ? 30 * Typography.logoKerning : 30 * 0.32,
                                                      offset: reduceMotion ? 0 : 14,
                                                      opacity: reduceMotion ? 1 : 0),
                              trigger: started) { view, state in
                view.overlay {
                    Text("CUTIN")
                        .font(Typography.logo(size: 30))
                        .kerning(state.kerning)
                        .foregroundStyle(ink)
                        .offset(y: state.offset)
                        .opacity(state.opacity)
                }
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: delay)
                    LinearKeyframe(1, duration: 0.22)
                }
                KeyframeTrack(\.offset) {
                    LinearKeyframe(14, duration: delay)
                    SpringKeyframe(0, duration: 0.42, spring: .smooth(duration: 0.42))
                }
                KeyframeTrack(\.kerning) {
                    LinearKeyframe(30 * 0.32, duration: delay)
                    SpringKeyframe(30 * Typography.logoKerning, duration: 0.45, spring: .smooth(duration: 0.45))
                }
            }
    }

    private struct MarkState {
        var kerning: CGFloat
        var offset: CGFloat
        var opacity: Double
    }
}

#Preview("인트로") {
    IntroView(onFinished: {})
        .environment(\.palette, Palette.light)
}

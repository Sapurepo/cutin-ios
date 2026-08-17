/* 인트로 — 앱을 켤 때 아이콘의 꽃잎 넷이 한 장씩 피고 CUTIN이 올라온다.
 *
 * **기다리는 시간을 새로 만들지 않는다.** 앱 시작 직후 `/users/me` 왕복(`AuthSession.restore`)이
 * 어차피 0.3~0.8초 걸리고, 0.3.0은 그동안 빈 배경이었다. 이 화면은 그 구간을 덮는 덮개다 —
 * 최소 0.9초(연출이 끝까지), 최대 1초(서버가 늦어도 더 붙잡지 않는다). 콜드 스타트에만 뜬다:
 * `AuthGate`가 앱 수명 동안 한 번 만들어지고 `restore()`도 한 번이라 백그라운드에서 돌아올 때는
 * 지나가지 않는다.
 *
 * 그림은 **앱 아이콘 그대로**다(`AppMark` — 아이콘 문서의 꽃잎 좌표·색). 홈 화면에서 누른
 * 아이콘이 화면 안에서 다시 피어나는 장면이라 다른 로고를 그리면 다른 앱이 된다. 리듬은
 * 연속 촬영 3·2·1처럼 120ms 간격으로 한 장씩(위 → 오른쪽 → 아래 → 왼쪽, 아이콘 레이어 순),
 * 넷째 장에 가벼운 햅틱 한 번. 이어서 워드마크가 넓게 벌어진 자간에서 로고 자간으로 조여들며
 * 올라온다.
 *
 * 움직임 줄이기가 켜져 있으면 완성된 그림을 0.4초 보여주고 끝난다. */

import SwiftUI

struct IntroView: View {
    /// 연출이 끝났다 — `AuthGate`가 이 뒤에 다음 화면으로 넘어간다.
    let onFinished: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var started = false

    /// 장 간격(초). 넷째 장이 0.36초에 피고 워드마크는 0.42초에 올라오기 시작한다.
    private static let beat: Double = 0.12
    private static let markSize: CGFloat = 156
    private static let total: Double = 0.95

    var body: some View {
        VStack(spacing: Spacing.x5) {
            mark
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

    // MARK: - 꽃잎 넷

    private var mark: some View {
        ZStack {
            ForEach(AppMark.petals) { petal in
                self.petal(petal)
            }
        }
        .frame(width: Self.markSize, height: Self.markSize)
    }

    /* 꽃잎 하나 — 중심에서 살짝 작게(0.7) 시작해 자리를 잡으며 나타난다. `keyframeAnimator`로
     * 장마다 시작 시각을 늦춘다 — 앞의 `hold` 구간이 그 지연이다. */
    @ViewBuilder
    private func petal(_ petal: AppMark.Petal) -> some View {
        let leaf = AppMarkPetal(petal: petal, size: Self.markSize)
        if reduceMotion {
            // 애니메이터를 아예 걸지 않는다 — 걸면 첫 프레임에 트랙 시작값(0.7 · 투명)이 스친다.
            leaf
        } else {
            let delay = Self.beat * Double(petal.id) + 0.05
            leaf.keyframeAnimator(initialValue: PetalState(scale: 0.7, opacity: 0),
                                  trigger: started) { view, state in
                view
                    .scaleEffect(state.scale)
                    .opacity(state.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: delay)
                    LinearKeyframe(1, duration: 0.14)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.7, duration: delay)
                    SpringKeyframe(1.0, duration: 0.36, spring: .bouncy(duration: 0.36, extraBounce: 0.04))
                }
            }
            .onChange(of: started) { _, _ in
                // 넷째 장 — 그 시각에 맞춰 가벼운 햅틱 한 번.
                guard petal.id == AppMark.petals.count - 1 else { return }
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }

    private struct PetalState {
        var scale: CGFloat
        var opacity: Double
    }

    // MARK: - 워드마크

    @ViewBuilder
    private var wordmark: some View {
        let ink = palette.textPrimary   // 애니메이터 클로저는 비격리라 환경을 밖에서 읽어 둔다
        if reduceMotion {
            Text("CUTIN")
                .font(Typography.logo(size: 30))
                .kerning(30 * Typography.logoKerning)
                .foregroundStyle(ink)
                .frame(width: 160, height: 36)
        } else {
            let delay = Self.beat * 3 + 0.11
            // 자간은 Text에만 걸리므로 글자를 애니메이터 안에서 그린다 — 밖의 자리만 고정해 둔다.
            Color.clear
                .frame(width: 160, height: 36)
                .keyframeAnimator(initialValue: MarkState(kerning: 30 * 0.32, offset: 14, opacity: 0),
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

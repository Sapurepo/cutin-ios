/* 테두리 스트로크 오버레이 — `.overlay { Shape().stroke(border) }` 반복 패턴(6곳) 통합.
 * 도형(RoundedRectangle/Capsule)과 색·굵기만 다르고 구조가 같아 제네릭 하나로 흡수한다. */

import SwiftUI

extension View {
    /// 도형 스트로크를 오버레이로 얹는다. 배경 도형과 같은 Shape를 넘길 것.
    ///
    /// SwiftUI의 `InsettableShape.strokeBorder`와 기하가 다르다 — 그쪽은 선을 도형 안쪽으로
    /// 밀어넣지만 이 오버레이는 경로 위에 선을 얹어 굵기의 절반이 배경 바깥으로 나간다.
    /// 이식 전 호출부 6곳이 모두 후자였고 그 렌더를 유지하려고 이름을 다르게 둔다.
    func tokenBorder<S: Shape>(_ shape: S, color: Color, lineWidth: CGFloat = 1) -> some View {
        overlay { shape.stroke(color, lineWidth: lineWidth) }
    }
}

#Preview("TokenBorder", traits: .sizeThatFitsLayout) {
    VStack(spacing: Spacing.x3) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            let palette = Palette.of(scheme)
            HStack(spacing: Spacing.x3) {
                Text("rect")
                    .padding(Spacing.x3)
                    .background(palette.surface, in: .rect(cornerRadius: Radius.sm))
                    .tokenBorder(RoundedRectangle(cornerRadius: Radius.sm), color: palette.border)
                Text("strong 1.5")
                    .padding(Spacing.x3)
                    .background(palette.surface, in: .rect(cornerRadius: Radius.md))
                    .tokenBorder(RoundedRectangle(cornerRadius: Radius.md),
                                 color: palette.borderStrong, lineWidth: 1.5)
                Text("capsule")
                    .padding(Spacing.x3)
                    .background(palette.surface, in: .capsule)
                    .tokenBorder(Capsule(), color: palette.border)
            }
            .font(Typography.chip)
            .foregroundStyle(palette.textPrimary)
            .padding(Spacing.x4)
            .background(palette.bg)
        }
    }
}

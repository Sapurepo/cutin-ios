/* 테두리 스트로크 오버레이 — `.overlay { Shape().stroke(border) }` 반복 패턴(6곳) 통합.
 * 도형(RoundedRectangle/Capsule)과 색·굵기만 다르고 구조가 같아 제네릭 하나로 흡수한다. */

import SwiftUI

extension View {
    /// 도형 스트로크를 오버레이로 얹는다. 배경 도형과 같은 Shape를 넘길 것.
    func strokedBorder<S: Shape>(_ shape: S, color: Color, lineWidth: CGFloat = 1) -> some View {
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
                    .strokedBorder(RoundedRectangle(cornerRadius: Radius.sm), color: palette.border)
                Text("strong 1.5")
                    .padding(Spacing.x3)
                    .background(palette.surface, in: .rect(cornerRadius: Radius.md))
                    .strokedBorder(RoundedRectangle(cornerRadius: Radius.md),
                                   color: palette.borderStrong, lineWidth: 1.5)
                Text("capsule")
                    .padding(Spacing.x3)
                    .background(palette.surface, in: .capsule)
                    .strokedBorder(Capsule(), color: palette.border)
            }
            .font(Typography.chip)
            .foregroundStyle(palette.textPrimary)
            .padding(Spacing.x4)
            .background(palette.bg)
        }
    }
}

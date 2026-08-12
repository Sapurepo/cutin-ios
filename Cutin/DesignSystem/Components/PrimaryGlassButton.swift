/* 주요 CTA 버튼 스타일 — `.buttonStyle(.glassProminent)` + tint 조합의 반복
 * (CaptureSetupView 촬영 시작, CaptureView 권한 허용) 통합. */

import SwiftUI

extension View {
    /// Liquid Glass prominent CTA. tint 기본값은 팔레트 accent가 아니라 호출부가 넘긴다 —
    /// 촬영 캔버스처럼 강제 다크인 화면은 white를 쓰기 때문.
    func primaryGlassButton(tint: Color) -> some View {
        buttonStyle(.glassProminent).tint(tint)
    }
}

#Preview("PrimaryGlassButton", traits: .sizeThatFitsLayout) {
    VStack(spacing: Spacing.x4) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            let palette = Palette.of(scheme)
            Button {} label: {
                Text("촬영 시작")
                    .font(Typography.font(.body, .semibold, size: 15))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.x4)
            }
            .primaryGlassButton(tint: palette.accent)
            .padding(Spacing.x4)
            .background(palette.bg)
        }
    }
}

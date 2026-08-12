/* 주요 CTA 버튼 스타일 — `.buttonStyle(.glassProminent)` + tint 조합의 반복
 * (CaptureSetupView 촬영 시작, CaptureView 카메라 권한 허용) 통합.
 * 권한 허용 버튼은 조상 `.tint(.white)`에 의존하고 있었는데, 통합하면서 tint를 호출부에
 * 명시하게 했다 — 그래야 CTA 스타일을 바꿀 때 이 헬퍼만 grep하면 전부 잡힌다. */

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
                    .font(Typography.buttonLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.x4)
            }
            .primaryGlassButton(tint: palette.accent)
            .padding(Spacing.x4)
            .background(palette.bg)
        }
    }
}

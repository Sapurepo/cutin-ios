/* 주요 CTA 버튼 스타일 — `.buttonStyle(.glassProminent)` + tint 조합의 반복
 * (CaptureSetupView 촬영 시작, CaptureView 카메라 권한 허용) 통합.
 * 권한 허용 버튼은 조상 `.tint(.white)`에 의존하고 있었는데, 통합하면서 tint를 호출부에
 * 명시하게 했다 — 그래야 CTA 스타일을 바꿀 때 이 헬퍼만 grep하면 전부 잡힌다. */

import SwiftUI

extension View {
    /// Liquid Glass prominent CTA. tint 기본값은 팔레트 accent가 아니라 호출부가 넘긴다 —
    /// 촬영 캔버스처럼 강제 다크인 화면은 white를 쓰기 때문.
    ///
    /// **라벨색도 여기서 정한다.** `.glassProminent`는 tint와 무관하게 라벨을 흰색으로 그려,
    /// tint가 밝으면(다크의 accent는 오프화이트, 촬영 캔버스의 white) 흰 알약 위의 흰 글씨가 된다 —
    /// 다크 모드의 "다음"·"저장"·"다시 시도"가 0.3.0 내내 거의 안 보였다(0.4.0 감사에서 발견).
    /// 기본은 팔레트 `accentOn`(accent 위의 글자색), white tint는 `label:`로 잉크를 넘긴다.
    func primaryGlassButton(tint: Color, label: Color? = nil) -> some View {
        modifier(PrimaryGlassButton(tint: tint, label: label))
    }

    /// 화면 폭을 채우는 CTA의 **라벨**에 붙인다 — 폰트·폭·높이가 화면마다 달라지면
    /// 편집 단계를 넘길 때 같은 자리의 버튼이 미묘하게 튄다.
    /// (`primaryGlassButton`은 스타일이라 라벨 치수를 정하지 못한다.)
    func primaryGlassLabel() -> some View {
        glassLabel()
    }

    /// 같은 치수, 색은 스타일에 맡긴다 — `.buttonStyle(.glass)`(채우지 않은 글래스) 위의 라벨용.
    /// 타인 프로필의 "팔로잉·친구"처럼 채움 CTA와 **같은 자리에서 번갈아 나오는** 버튼이 쓴다.
    func glassLabel() -> some View {
        font(Typography.buttonLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.x4)
    }
}

private struct PrimaryGlassButton: ViewModifier {
    let tint: Color
    let label: Color?
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content
            .buttonStyle(.glassProminent)
            .tint(tint)
            .foregroundStyle(label ?? palette.accentOn)
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

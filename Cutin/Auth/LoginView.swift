/* 로그인 화면 — 명세 §2. 0.2.0에서는 카카오 하나다.
 *
 * 서비스 설명을 늘어놓지 않는다. 앱을 처음 열었을 때 필요한 정보는 "무슨 앱인지"와 "어떻게
 * 들어가는지" 둘뿐이고, 나머지는 들어가서 보면 된다.
 *
 * "무슨 앱인지"는 문장이 아니라 **물건**으로 말한다 — 인화된 네컷 스트립 두 장(`StripArt`).
 * 0.3.0의 로고 한 줄은 첫인상이 가장 약한 화면이었다(0.4.0 감사). 사진을 번들하지 않는 이유는
 * StripArt 머리말에.
 *
 * 카카오 버튼만 브랜드 색(`#FEE500`)을 쓴다 — 카카오 디자인 가이드가 요구하는 색이라
 * 모노크롬 토큰에 넣지 않고 이 파일에 콘텐츠 색으로 둔다(`FrameSkin`의 프레임 색과 같은 논리다). */

import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isSettled = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.x8)
            hero
            Spacer(minLength: Spacing.x6)
            mark
            Spacer(minLength: Spacing.x8)
            kakaoButton
            if let failure = session.failure {
                Text(failure)
                    .font(Typography.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.x3)
            }
            Spacer().frame(height: Spacing.x8)
        }
        .padding(.horizontal, Spacing.x6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bg)
        .onAppear {
            guard !reduceMotion else { isSettled = true; return }
            withAnimation(Motion.emphasized.delay(0.15)) { isSettled = true }
        }
    }

    /* 스트립 두 장이 겹쳐 놓인 모양 — 포토부스에서 막 뽑아 든 것처럼. 등장할 때 살짝 벌어지며
     * 자리를 잡는다(한 번, 0.5초). 움직임 줄이기가 켜져 있으면 처음부터 놓인 상태다. */
    private var hero: some View {
        ZStack {
            StripArt(layout: .strip4, skin: .lavender, width: 118)
                .rotationEffect(.degrees(isSettled ? 9 : 2))
                .offset(x: isSettled ? 54 : 12, y: isSettled ? 10 : 0)
                .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
            StripArt(layout: .strip4, skin: .white, width: 124)
                .rotationEffect(.degrees(isSettled ? -6 : -1))
                .offset(x: isSettled ? -30 : -6)
                .shadow(color: .black.opacity(0.14), radius: 22, y: 12)
        }
        .frame(height: 400)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var mark: some View {
        VStack(spacing: Spacing.x3) {
            // 라틴 전용 서체 — 로고이므로 Geist가 맞다(한글에 걸면 시스템 폰트로 폴백한다).
            Text("CUTIN")
                .font(Typography.logo(size: 34))
                .kerning(34 * Typography.logoKerning)
                .foregroundStyle(palette.textPrimary)
            Text("네 컷으로 남기는 오늘")
                .font(Typography.body)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var kakaoButton: some View {
        Button {
            Task { await session.signInWithKakao() }
        } label: {
            HStack(spacing: Spacing.x2) {
                Image(systemName: "message.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(session.isAuthenticating ? "로그인 중…" : "카카오로 시작하기")
                    .font(Typography.buttonLabel)
            }
            .foregroundStyle(Color(hex: 0x191600))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.x4)
            .background(Color(hex: 0xFEE500), in: .rect(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(session.isAuthenticating)
        .opacity(session.isAuthenticating ? 0.6 : 1)
    }
}

#Preview("로그인") {
    LoginView()
        .environment(AuthSession(client: APIClient()))
        .environment(\.palette, Palette.light)
}

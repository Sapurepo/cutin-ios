/* 로그인 화면 — 명세 §2. 0.2.0에서는 카카오 하나다.
 *
 * 서비스 설명을 늘어놓지 않는다. 앱을 처음 열었을 때 필요한 정보는 "무슨 앱인지"와 "어떻게
 * 들어가는지" 둘뿐이고, 나머지는 들어가서 보면 된다.
 *
 * 카카오 버튼만 브랜드 색(`#FEE500`)을 쓴다 — 카카오 디자인 가이드가 요구하는 색이라
 * 모노크롬 토큰에 넣지 않고 이 파일에 콘텐츠 색으로 둔다(`FrameSkin`의 프레임 색과 같은 논리다). */

import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            mark
            Spacer()
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
    }

    private var mark: some View {
        VStack(spacing: Spacing.x3) {
            // 라틴 전용 서체 — 로고이므로 Geist가 맞다(한글에 걸면 시스템 폰트로 폴백한다).
            Text("CUTIN")
                .font(Typography.font(.latin, .bold, size: 34))
                .kerning(4)
                .foregroundStyle(palette.textPrimary)
            Text("네 컷으로 남기는 오늘")
                .font(Typography.bodyText)
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

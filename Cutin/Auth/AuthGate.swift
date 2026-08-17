/* 로그인 여부로 갈리는 최상단 분기.
 *
 * `RootView`에 조건을 넣지 않고 한 겹을 두는 이유: 탭 셸은 로그인한 뒤에야 의미가 있고,
 * 셸 안에서 분기하면 로그아웃할 때 탭 상태·네비게이션 스택이 살아남아 다음 로그인에 이전
 * 사용자의 화면이 남는다. 뷰 정체성이 갈리면 SwiftUI가 알아서 버린다.
 *
 * 0.1.0까지는 앱을 켜면 곧바로 피드였다(인증 범위 밖). 그 진입점이 여기로 바뀐다. */

import SwiftUI

struct AuthGate: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme

    /* 이 기기에서 팁(§3.5)을 봤는지. 계정이 아니라 **기기** 상태다 — 서버에 대응 필드가 없고,
     * 도움말이 재설치 후 한 번 더 뜨는 것은 사고가 아니다. 재열람은 프로필의 도움말 메뉴다. */
    @AppStorage("tips.seen") private var hasSeenTips = false

    var body: some View {
        content
            /* 앱을 켤 때 한 번. `.task`는 뷰가 사라지면 취소되는데 이 뷰는 앱 수명 동안
             * 살아 있으므로 취소 걱정이 없다. */
            .task { await session.restore() }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .restoring:
            /* 스플래시를 따로 그리지 않는다. Keychain 읽기는 즉시 끝나고 `/users/me` 왕복만
             * 남으므로 대개 한 프레임이다 — 로고를 띄우면 오히려 번쩍인다. */
            Color(Palette.of(colorScheme).bg).ignoresSafeArea()
        case .signedOut:
            LoginView()
                .environment(\.palette, Palette.of(colorScheme))
        /* 온보딩을 탭 셸 **안**이 아니라 여기서 가른다. 셸 안에 시트로 띄우면 그 뒤에 피드가
         * 이미 떠 있고, 온보딩을 마치지 않은 계정은 닉네임이 없어 포스트에 이름을 붙일 수 없다.
         * 서버도 같은 판단이다 — `onboardingCompleted`를 프로필에 실어 준다. */
        case .signedIn(let profile) where !profile.onboardingCompleted:
            OnboardingView(saved: profile.nickname)
                .environment(\.palette, Palette.of(colorScheme))
        /* 온보딩을 마친 직후 팁 한 번(§3.5). 셸보다 먼저 가르는 이유는 온보딩과 같다 —
         * 셸 위에 시트로 얹으면 뒤에서 피드가 이미 돌기 시작한다. */
        case .signedIn where !hasSeenTips:
            TipsView(onStart: { hasSeenTips = true })
                .environment(\.palette, Palette.of(colorScheme))
        case .signedIn:
            RootView()
        }
    }
}

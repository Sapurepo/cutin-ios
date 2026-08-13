/* 저장된 포스트와 진행 중인 촬영은 화면이 아니라 앱이 가진 상태라 여기서 만들어 환경으로 내린다.
 * 어느 탭에서든 읽고, 탭을 넘나들어도 같은 값이어야 한다.
 *
 * 촬영 화면이 떠 있는지(`AppCoordinator`)는 셸의 관심사라 RootView에 남겨 뒀다. 그래서 셸이
 * 다시 만들어지면 촬영 커버는 닫힌다 — 그때 컷을 잃지 않는 건 draft 영속(§5.3)의 일이다. */

import SwiftUI

@main
struct CutinApp: App {
    @State private var store: PostStore
    @State private var flow = CaptureFlow()

    /* 전송 계층과 세션은 앱 하나에 하나다. 토큰과 진행 중인 재발급이 여기 있으므로 화면마다
     * 새로 만들면 각 화면이 자기 토큰을 들고 따로 재발급한다. */
    @State private var session: AuthSession

    /* 템플릿·프레임 목록. 촬영 설정과 편집 1단계가 함께 읽고 앱 실행당 한 번 받으므로
     * 앱이 소유한다 — 화면마다 만들면 편집으로 넘어갈 때마다 다시 받는다. */
    @State private var catalog: TemplateCatalog
    /// 발행 진행 상태. 촬영 커버가 닫혀도 살아야 하므로 앱이 소유한다.
    @State private var publisher: PostPublisher

    init() {
        KakaoLogin.initialize()
        /* 세션과 카탈로그가 **같은 전송 계층**을 쓴다. 따로 만들면 카탈로그 쪽 클라이언트에는
         * 액세스 토큰도 재발급 경로도 없어서 `/templates`(auth 필요)가 401로 끝난다. */
        let client = APIClient()
        session = AuthSession(client: client)
        catalog = TemplateCatalog(client: client)
        store = PostStore(client: client)
        publisher = PostPublisher(client: client)
    }

    var body: some Scene {
        WindowGroup {
            AuthGate()
                .environment(store)
                .environment(flow)
                .environment(session)
                .environment(catalog)
                .environment(publisher)
                /* 카카오톡에서 되돌아오는 URL. `RootView`가 아니라 여기에 두는 이유는
                 * 로그인 화면(게이트의 다른 분기)에서도 받아야 하기 때문이다. */
                .onOpenURL { url in _ = KakaoLogin.handle(url) }
        }
    }
}

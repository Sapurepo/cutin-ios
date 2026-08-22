/* 저장된 포스트와 진행 중인 촬영은 화면이 아니라 앱이 가진 상태라 여기서 만들어 환경으로 내린다.
 * 어느 탭에서든 읽고, 탭을 넘나들어도 같은 값이어야 한다.
 *
 * 촬영 화면이 떠 있는지(`AppCoordinator`)는 셸의 관심사라 RootView에 남겨 뒀다. 그래서 셸이
 * 다시 만들어지면 촬영 커버는 닫힌다 — 그때 컷을 잃지 않는 건 draft 영속(§5.3)의 일이다. */

import SwiftUI

@main
struct CutinApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

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
    /// 친구 관계와 댓글. 여러 화면이 같은 값을 읽으므로 앱이 소유한다.
    @State private var social: SocialStore
    @State private var comments: CommentStore
    /// 알림 목록·설정과 푸시 등록. 피드 배지가 읽으므로 앱이 소유한다.
    @State private var notifications: NotificationStore
    @State private var push: PushRegistrar

    init() {
        KakaoLogin.initialize()
        /* 세션과 카탈로그가 **같은 전송 계층**을 쓴다. 따로 만들면 카탈로그 쪽 클라이언트에는
         * 액세스 토큰도 재발급 경로도 없어서 `/templates`(auth 필요)가 401로 끝난다. */
        let client = APIClient()
        let session = AuthSession(client: client)
        let store = PostStore(client: client)
        let social = SocialStore(client: client)
        let comments = CommentStore(client: client)
        let notifications = NotificationStore(client: client)

        /* 계정이 바뀌면 서버에서 받아 둔 것을 전부 버린다.
         *
         * 스토어는 앱 수명이고 로그아웃은 화면만 바꾸므로, 비우지 않으면 **다음 계정이 이전
         * 계정의 피드를 본다.** 화면이 다시 만들어져도 `hasLoaded == true`라 `loadFeed()`가
         * 그대로 돌아 나가고, 커서가 남아 있으면 이전 계정 목록 위에 새 계정 페이지를 덧붙인다.
         * 알림도 같다 — 비우지 않으면 이전 계정의 알림 목록과 미읽음 배지가 남는다.
         *
         * `TemplateCatalog`는 비우지 않는다 — 템플릿·프레임은 계정의 것이 아니라 서버 전체의
         * 것이고, 비우면 다음 로그인이 왕복 둘을 다시 낸다. */
        session.onAccountChange = {
            store.reset()
            social.reset()
            comments.reset()
            notifications.reset()
        }

        /* 친구 관계가 바뀌면 친구공개 포스트의 노출이 달라진다. 서버는 즉시 반영하지만
         * (cutin-backend#17) 앱이 받아 둔 피드는 옛 범위 그대로라 맞팔한 친구의 글이 들어오지
         * 않는다. 관계는 `SocialStore`가, 그 노출은 `PostStore`가 갖고 있어 둘을 이어야 하는데,
         * 스토어끼리 서로를 알게 하지 않고 위 `onAccountChange`와 같은 자리에서 잇는다. */
        social.onFriendshipChange = { userId in
            await store.friendshipChanged(with: userId)
        }

        self.session = session
        self.store = store
        self.social = social
        self.comments = comments
        self.notifications = notifications
        catalog = TemplateCatalog(client: client)
        publisher = PostPublisher(client: client)

        let registrar = PushRegistrar(client: client)
        push = registrar
        /* APNs 토큰은 UIKit이 앱 델리게이트 콜백으로만 준다 — SwiftUI에 대응하는 훅이 없다.
         * 델리게이트에 등록기를 넘겨 받은 토큰을 그대로 흘려보낸다. */
        AppDelegate.registrar = registrar
    }

    var body: some Scene {
        WindowGroup {
            AuthGate()
                .environment(store)
                .environment(flow)
                .environment(session)
                .environment(catalog)
                .environment(publisher)
                .environment(social)
                .environment(comments)
                .environment(notifications)
                .environment(push)
                /* 카카오톡에서 되돌아오는 URL. `RootView`가 아니라 여기에 두는 이유는
                 * 로그인 화면(게이트의 다른 분기)에서도 받아야 하기 때문이다. */
                .onOpenURL { url in _ = KakaoLogin.handle(url) }
        }
    }
}

/* 라우트 → 화면. 네 탭이 같은 목적지 집합을 쓰므로 한곳에 둔다.
 *
 * 0.1.0은 탭마다 `navigationDestination`을 손으로 적었고 케이스가 하나(포스트 상세)뿐이라
 * 그래도 괜찮았다. 목적지가 셋이 되면서 탭마다 세 줄씩 적게 되고, 하나를 빠뜨리면 **그 탭에서만
 * 링크가 죽는다** — 컴파일러가 잡아 주지 않는 종류의 실수다. */

import SwiftUI

extension View {
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .postDetail(let id):
                PostDetailView(id: id)
            case .userProfile(let id):
                UserProfileView(id: id)
            case .notifications:
                NotificationsView()
            case .notificationSettings:
                NotificationSettingsView()
            case .tips:
                TipsView(onStart: nil)
            #if DEBUG
            case .designCatalog:
                DesignCatalogView()
            #endif
            }
        }
    }
}

/* 친구 탭 — 친구 관계는 서버가 소유하므로(명세 §9) 0.1.0에서는 목록을 만들지 않는다.
 *
 * RN판 `apps/mobile/src/app/friends/index.tsx`는 하드코딩 목록을 그리는 no-op 목업이라
 * 이식하면 릴리즈 스크린샷에 거짓 데이터가 남는다. 대신 서버 없이도 진짜로 동작하는
 * 초대 공유 하나만 둔다 — 0.2.0에서 친구 목록이 추가돼도 이 액션은 그대로 살아남는다. */

import SwiftUI

struct FriendsView: View {
    @Environment(\.palette) private var palette

    /// 앱 배포 전이라 딥링크 URL이 없다. 링크를 지어내지 않고 문구만 공유한다.
    private let inviteMessage = "같이 컷 남기자! CUTIN에서 4컷 찍고 하루 한 번 공유해요."

    var body: some View {
        EmptyStateView(
            title: "함께할 친구를 불러요",
            message: "친구 목록은 계정이 붙는 다음 버전에서 열려요.\n먼저 초대장을 보내 둘 수 있어요.",
            systemImage: "person.2"
        ) {
            ShareLink(item: inviteMessage) {
                Text("초대장 보내기")
                    .font(Typography.buttonLabel)
                    .padding(.horizontal, Spacing.x5)
                    .padding(.vertical, Spacing.x3)
            }
            .primaryGlassButton(tint: palette.accent)
        }
        .background(palette.bg)
        .navigationTitle(AppTab.friends.title)
    }
}

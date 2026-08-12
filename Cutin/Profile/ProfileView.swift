/* 프로필 탭 — 셸이 5탭을 다 세우기 위한 자리. 닉네임·그리드·통계는 다음 브랜치에서 채운다.
 * RN판의 하드코딩 통계(`{posts:"24", friends:"132"}`)는 이식하지 않는다 — 거짓 수치를
 * 화면에 올리는 순간 스크린샷이 증거로서 무의미해진다. */

import SwiftUI

struct ProfileView: View {
    @Environment(\.palette) private var palette

    var body: some View {
        EmptyStateView(
            title: "내 기록",
            message: "남긴 컷과 프로필이 이 자리에 모여요",
            systemImage: "person.crop.circle"
        )
        .background(palette.bg)
        .navigationTitle(AppTab.profile.title)
    }
}

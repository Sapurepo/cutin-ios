/* 기록 보관 탭 — 명세 §4.2-5 / §6·§7의 보관함. 보관 토글과 목록은 다음 브랜치에서 붙인다. */

import SwiftUI

struct ArchiveView: View {
    @Environment(\.palette) private var palette

    var body: some View {
        EmptyStateView(
            title: "보관한 컷이 없어요",
            message: "마음에 남는 컷을 보관하면 여기 모여요",
            systemImage: "bookmark"
        )
        .background(palette.bg)
        .navigationTitle(AppTab.archive.title)
    }
}

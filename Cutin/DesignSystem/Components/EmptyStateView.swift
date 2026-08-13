/* 빈 상태 — 피드·친구·프로필·보관 네 화면이 같은 구성(아이콘 → 제목 → 안내 → 선택적 액션)을 쓴다.
 * 액션이 클로저가 아니라 `@ViewBuilder`인 이유: 친구 탭은 ShareLink를 넣어야 하고
 * ShareLink는 버튼이 아니라 뷰다. */

import SwiftUI

struct EmptyStateView<Action: View>: View {
    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder var action: () -> Action

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Spacing.x3) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(palette.textSecondary)
                .padding(.bottom, Spacing.x1)

            Text(title)
                .font(Typography.headline)
                .foregroundStyle(palette.textPrimary)

            Text(message)
                .font(Typography.bodyText)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)

            action()
                .padding(.top, Spacing.x2)
        }
        .padding(Spacing.x8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(title: String, message: String, systemImage: String) {
        self.init(title: title, message: message, systemImage: systemImage) { EmptyView() }
    }
}

#Preview("EmptyStateView", traits: .sizeThatFitsLayout) {
    VStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            let palette = Palette.of(scheme)
            VStack(spacing: 0) {
                EmptyStateView(
                    title: "아직 남긴 컷이 없어요",
                    message: "촬영 탭에서 첫 컷을 찍어보세요",
                    systemImage: "square.grid.2x2"
                )
                EmptyStateView(
                    title: "함께할 친구가 없어요",
                    message: "초대 링크를 보내 같이 컷을 남겨보세요",
                    systemImage: "person.2"
                ) {
                    Button("초대하기") {}
                        .buttonStyle(.glass)
                }
            }
            .frame(height: 460)
            .background(palette.bg)
            .environment(\.palette, palette)
        }
    }
}

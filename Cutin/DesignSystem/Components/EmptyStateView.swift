/* 빈 상태 — 피드·친구·프로필·보관·알림이 같은 구성(그림 → 제목 → 안내 → 선택적 액션)을 쓴다.
 * 액션이 클로저가 아니라 `@ViewBuilder`인 이유: 친구 탭은 ShareLink를 넣어야 하고
 * ShareLink는 버튼이 아니라 뷰다.
 *
 * 그림은 **옅은 면 위의 심볼**이 기본이고, 화면이 자기 물건(빈 스트립 등)을 넘길 수 있다.
 * 0.3.0은 원 안의 회색 심볼 하나라 팁·보관·촬영 폴백이 구분되지 않았다(0.4.0 감사 G5). */

import SwiftUI

struct EmptyStateView<Illustration: View, Action: View>: View {
    let title: String
    let message: String
    @ViewBuilder var illustration: () -> Illustration
    @ViewBuilder var action: () -> Action

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Spacing.x3) {
            illustration()
                .padding(.bottom, Spacing.x2)
            Text(title)
                .font(Typography.headline)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            action()
                .padding(.top, Spacing.x2)
        }
        .padding(Spacing.x8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 기본 그림 — 옅은 면(sunken) 위의 심볼. 원이 아니라 둥근 사각인 이유: 카드·칩과 같은 어휘다.
struct EmptySymbol: View {
    let systemImage: String
    @Environment(\.palette) private var palette
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 28, weight: .regular))
            .foregroundStyle(palette.textSecondary)
            .frame(width: 72, height: 72)
            .background(palette.surfaceSunken, in: .rect(cornerRadius: Radius.lg))
            .accessibilityHidden(true)
    }
}

extension EmptyStateView where Illustration == EmptySymbol {
    init(title: String, message: String, systemImage: String, @ViewBuilder action: @escaping () -> Action) {
        self.init(title: title, message: message,
                  illustration: { EmptySymbol(systemImage: systemImage) }, action: action)
    }
}
extension EmptyStateView where Illustration == EmptySymbol, Action == EmptyView {
    init(title: String, message: String, systemImage: String) {
        self.init(title: title, message: message,
                  illustration: { EmptySymbol(systemImage: systemImage) }, action: { EmptyView() })
    }
}
extension EmptyStateView where Action == EmptyView {
    init(title: String, message: String, @ViewBuilder illustration: @escaping () -> Illustration) {
        self.init(title: title, message: message, illustration: illustration, action: { EmptyView() })
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

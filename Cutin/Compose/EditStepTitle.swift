/* 편집 3단계의 제목 — 지금이 몇 번째인지 함께 보여준다.
 *
 * 템플릿 · 보정 · 마무리는 같은 골격(미리보기 · 칩 · CTA)이라 제목만으로는 몇 번째 화면인지,
 * 앞으로 몇 번 더 눌러야 하는지 모른다(0.4.0 감사). "1 / 3"을 제목 아래 작게 둔다 — 진행 막대는
 * 세 단계에 과하고, 큰 숫자는 제목과 싸운다. */

import SwiftUI

private struct EditStepTitle: ViewModifier {
    let title: String
    let step: Int
    static let total = 3

    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            // 제목은 principal 뷰가 그리지만 navigationTitle도 준다 — 다음 화면의 뒤로 버튼 라벨과
            // VoiceOver가 이 값을 읽는다.
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(title)
                            .font(Typography.headline)
                            .foregroundStyle(palette.textPrimary)
                        Text("\(step) / \(Self.total)")
                            .font(Typography.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
    }
}

extension View {
    /// 편집 단계 제목 — `step`은 1부터.
    func editStepTitle(_ title: String, step: Int) -> some View {
        modifier(EditStepTitle(title: title, step: step))
    }
}

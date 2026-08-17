/* 선택형 칩 — CaptureSetupView(컷 수)와 ComposeView(템플릿·보정)에 중복돼 있던 구현 통합.
 *
 * 선택 = **옅은 면 + 잉크 테두리 + 굵은 글씨**, 비선택 = surface + border. 0.3.0의 검정 채움을
 * 버린 이유: 켜진 칩과 CTA가 같은 검정이라 한 화면에 "가장 중요한 것"이 서넛이었다(감사 G1).
 * 채움이 아니라 옅은 면인 이유: 칩은 여럿 중 하나가 켜진 상태이지 눌러야 할 것이 아니다. */

import SwiftUI

struct CutinChip: View {
    enum Style {
        /// 균등 폭 사각 칩 — 컷 수 선택처럼 행을 가득 채우는 그룹용
        case block
        /// 내용 폭 캡슐 칩 — 가로 스크롤 스트립용
        case capsule
    }

    let label: String
    let selected: Bool
    var style: Style = .capsule
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            switch style {
            case .block:
                text
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.x3)
                    .background(fill, in: .rect(cornerRadius: Radius.sm))
                    .tokenBorder(RoundedRectangle(cornerRadius: Radius.sm), color: stroke)
            case .capsule:
                text
                    .padding(.horizontal, Spacing.x3)
                    .padding(.vertical, Spacing.x2)
                    .background(fill, in: .capsule)
                    .tokenBorder(Capsule(), color: stroke)
            }
        }
        .buttonStyle(.plain)
    }

    private var text: some View {
        Text(label)
            .font(selected ? Typography.font(.body, .semibold, size: 12) : Typography.chip)
            .foregroundStyle(selected ? palette.brandInk : palette.textPrimary)
    }

    private var fill: Color { selected ? palette.brandSoft : palette.surface }
    private var stroke: Color { selected ? palette.brand : palette.border }
}

#Preview("CutinChip", traits: .sizeThatFitsLayout) {
    VStack(spacing: Spacing.x4) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            let palette = Palette.of(scheme)
            VStack(spacing: Spacing.x3) {
                HStack(spacing: Spacing.x2) {
                    CutinChip(label: "4컷", selected: true, style: .block) {}
                    CutinChip(label: "6컷", selected: false, style: .block) {}
                }
                HStack(spacing: Spacing.x2) {
                    CutinChip(label: "원본", selected: true) {}
                    CutinChip(label: "필름", selected: false) {}
                    CutinChip(label: "흑백", selected: false) {}
                }
            }
            .padding(Spacing.x4)
            .background(palette.bg)
            .environment(\.palette, palette)
        }
    }
}

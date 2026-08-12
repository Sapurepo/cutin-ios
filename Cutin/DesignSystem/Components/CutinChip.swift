/* 선택형 칩 — CaptureSetupView(컷 수)와 ComposeView(템플릿·보정)에 중복돼 있던 구현 통합.
 * 선택 = accent 채움 + 테두리 없음, 비선택 = surface + border 스트로크. 위계는 FILL로만 만든다. */

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
                    .strokedBorder(RoundedRectangle(cornerRadius: Radius.sm), color: stroke)
            case .capsule:
                text
                    .padding(.horizontal, Spacing.x3)
                    .padding(.vertical, Spacing.x2)
                    .background(fill, in: .capsule)
                    .strokedBorder(Capsule(), color: stroke)
            }
        }
        .buttonStyle(.plain)
    }

    private var text: some View {
        Text(label)
            .font(Typography.chip)
            .foregroundStyle(selected ? palette.accentOn : palette.textPrimary)
    }

    private var fill: Color { selected ? palette.accent : palette.surface }
    private var stroke: Color { selected ? .clear : palette.border }
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

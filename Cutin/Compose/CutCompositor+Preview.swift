/* 합성기 검증 프리뷰 — 테스트 타깃이 없는 동안 컷 수 × 레이아웃 조합을 눈으로 확인하는 수단.
 * 뷰 트리를 흉내내지 않고 **실제 합성기를 돌려** 그리므로 셀 순서·거터·프레임·푸터가 그대로 보인다.
 * 컷에 번호를 박아 두어 `CutLayoutEngine`이 내놓는 순서가 컷 인덱스와 맞는지 읽을 수 있다. */

#if DEBUG
import SwiftUI

private let previewLayouts: [CutLayout] = [.grid2x2, .row, .bigLeft, .strip]

/// 번호가 박힌 단색 컷 — 셀 순서를 읽기 위한 입력.
private func numberedCuts(_ count: Int) -> [UIImage] {
    let size = CGSize(width: 400, height: 300)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true

    return (0..<count).map { index in
        UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(hue: CGFloat(index) / CGFloat(max(count, 1)),
                    saturation: 0.45, brightness: 0.85, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            let label = NSAttributedString(
                string: "\(index + 1)",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 160, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]
            )
            let bounds = label.size()
            label.draw(at: CGPoint(x: (size.width - bounds.width) / 2,
                                   y: (size.height - bounds.height) / 2))
        }
    }
}

private func composed(_ count: CutCount, _ layout: CutLayout, _ skin: FrameSkin, cuts: Int? = nil) -> UIImage {
    CutCompositor.render(CompositionRequest(
        images: numberedCuts(cuts ?? count.rawValue),
        count: count,
        layout: layout,
        skin: skin,
        filter: .original,
        stampDate: Date(timeIntervalSince1970: 0),
        outputWidth: 220
    ))
}

private func labeled(_ title: String, _ image: UIImage) -> some View {
    VStack(spacing: Spacing.x1) {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 110)
        Text(title)
            .font(Typography.caption)
            .foregroundStyle(.secondary)
    }
}

#Preview("레이아웃 16조합", traits: .sizeThatFitsLayout) {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.x4) {
            ForEach(CutCount.allCases) { count in
                Text(count.label)
                    .font(Typography.bodyText)
                HStack(alignment: .top, spacing: Spacing.x3) {
                    ForEach(previewLayouts, id: \.self) { layout in
                        labeled(layout.rawValue, composed(count, layout, FrameSkins.white))
                    }
                }
            }
        }
        .padding(Spacing.x4)
    }
}

#Preview("프레임 스킨", traits: .sizeThatFitsLayout) {
    ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: Spacing.x3) {
            ForEach(FrameSkins.all) { skin in
                labeled(skin.id, composed(.four, .grid2x2, skin))
            }
        }
        .padding(Spacing.x4)
    }
}

/* 빈 슬롯 — 이전 구현은 잉크 팔레트를 역참조해 흰 프레임 위에 검은 구멍을 뚫었다.
 * 지금은 프레임 색에서 파생시킨다. (촬영 플로우는 컷을 다 채운 뒤에만 합성으로 넘어가므로
 * 실제로 도달하지 않는 상태지만, 합성기는 순수 함수라 이 입력도 정의돼 있어야 한다.) */
#Preview("빈 슬롯", traits: .sizeThatFitsLayout) {
    HStack(alignment: .top, spacing: Spacing.x3) {
        labeled("basic 2/4", composed(.four, .grid2x2, FrameSkins.basic, cuts: 2))
        labeled("white 2/4", composed(.four, .grid2x2, FrameSkins.white, cuts: 2))
        labeled("cherry 2/4", composed(.four, .grid2x2, FrameSkins.cherry, cuts: 2))
    }
    .padding(Spacing.x4)
}
#endif

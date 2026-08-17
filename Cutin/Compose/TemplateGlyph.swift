/* 배치 글리프 — 템플릿의 슬롯을 작은 도형으로 그린다. 촬영 설정(배치 미리보기)과
 * 편집 1단계(배치 칩)가 쓴다(호출부 2곳).
 *
 * 이름("포토부스 스트립")만으로는 어떤 배치인지 눌러 봐야 알았다(0.4.0 감사). 서버가 슬롯을 주므로
 * 그릴 수 있고, 합성기와 같은 계산(`CutGeometry.cells`)이라 실제 배치와 같은 그림이다. */

import SwiftUI

struct TemplateGlyph: View {
    let template: Template
    /// 글리프 높이 — 세로 스트립도 이 높이 안에 들어오게 폭을 비율로 잡는다.
    var height: CGFloat = 44
    var selected = false

    @Environment(\.palette) private var palette

    var body: some View {
        let hpw = CutGeometry.heightPerWidth(template.aspectRatio)
        // 세로가 긴 배치는 높이에, 가로가 긴 배치는 폭(높이의 1.6배)에 맞춘다.
        let width = min(height / hpw, height * 1.6)
        let gridHeight = width * hpw
        let rect = CGRect(x: 0, y: 0, width: width, height: gridHeight)
        Canvas { context, _ in
            for cell in CutGeometry.cells(template.slots, in: rect, gutter: 2) where !cell.isEmpty {
                context.fill(Path(roundedRect: cell, cornerRadius: 1.5),
                             with: .color(selected ? palette.brand : palette.borderStrong))
            }
        }
        .frame(width: width, height: gridHeight)
        .accessibilityHidden(true)
    }
}

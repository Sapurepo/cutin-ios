/* 합성기 검증 프리뷰 — 테스트 타깃이 없는 동안 템플릿 × 프레임 조합을 눈으로 확인하는 수단.
 * 뷰 트리를 흉내내지 않고 **실제 합성기를 돌려** 그리므로 셀 순서·거터·프레임·푸터가 그대로 보인다.
 * 컷에 번호를 박아 두어 `CutGeometry`가 내놓는 순서가 컷 인덱스와 맞는지 읽을 수 있다.
 *
 * ## 표본 데이터를 여기 두는 이유
 *
 * 템플릿·프레임은 이제 서버에서 오고 프리뷰는 네트워크를 쓸 수 없다. 그래서 **서버 시드와 같은
 * 값**을 표본으로 둔다(`seedTemplates.ts`·`seedFrames.ts`). 앱 코드가 참조하지 않는 `#if DEBUG`
 * 표본이므로 "로컬 레지스트리 부활"이 아니다 — 어긋나면 프리뷰만 실제와 달라진다.
 *
 * 여기 값이 서버와 갈라졌는지 의심되면 `Scripts/contract/openapi.json`을 갈고
 * 계약 하니스를 돌리는 편이 빠르다. */

#if DEBUG
import SwiftUI

// MARK: - 표본 (서버 시드와 같은 값)

private let sampleID = UUID(uuidString: "3f2c1b4a-5d6e-4f70-8a9b-0c1d2e3f4a5b")!

/// 격자를 0~1 비율로 편다 — 서버 `grid(columns, rows)`와 같은 계산이다.
private func grid(_ columns: Int, _ rows: Int) -> [TemplateSlot] {
    (0..<rows).flatMap { row in
        (0..<columns).map { column in
            TemplateSlot(
                x: Double(column) / Double(columns),
                y: Double(row) / Double(rows),
                width: 1 / Double(columns),
                height: 1 / Double(rows)
            )
        }
    }
}

private func template(_ code: String, _ name: String, _ aspectRatio: String,
                      _ slots: [TemplateSlot]) -> Template {
    Template(id: sampleID, code: code, name: name, cutCount: slots.count,
             aspectRatio: aspectRatio, slots: slots)
}

/// 서버 템플릿 8종.
private let sampleTemplates: [Template] = [
    template("single", "한 컷", "3:4", grid(1, 1)),
    template("strip2", "두 컷 세로", "1:2", grid(1, 2)),
    template("pair2", "두 컷 가로", "2:1", grid(2, 1)),
    template("grid4", "네 컷", "1:1", grid(2, 2)),
    template("strip4", "포토부스 스트립", "1:3", grid(1, 4)),
    template("strip4wide", "와이드 스트립", "3:1", grid(4, 1)),
    template("bigLeft", "빅 레프트", "1:1", [
        TemplateSlot(x: 0, y: 0, width: 0.615385, height: 1),
        TemplateSlot(x: 0.615385, y: 0, width: 0.384615, height: 0.333333),
        TemplateSlot(x: 0.615385, y: 0.333333, width: 0.384615, height: 0.333333),
        TemplateSlot(x: 0.615385, y: 0.666667, width: 0.384615, height: 0.333333),
    ]),
    template("grid6", "여섯 컷", "2:3", grid(2, 3)),
]

/// 360pt 설계 폭 기준 px → 비율. 서버 `ratio(px)`와 같다.
private func ratio(_ px: Double) -> Double { px / 360 }

private func frame(_ code: String, _ bg: String, _ fg: String,
                   stamped: Bool = true) -> Frame {
    Frame(
        id: sampleID, code: code, name: code, background: bg, foreground: fg,
        padding: ratio(stamped ? 12 : 4),
        gutter: ratio(stamped ? 8 : 4),
        cellRadius: ratio(stamped ? 2 : 3),
        footer: stamped ? ServerEnum(.logoDate) : nil
    )
}

/// 서버 프레임 8종.
private let sampleFrames: [Frame] = [
    frame("basic", "#1E1E21", "#F5F5F4", stamped: false),
    frame("white", "#FFFFFF", "#0A0A0B"),
    frame("noir", "#111113", "#F5F5F4"),
    frame("peach", "#FFD9CF", "#8A3B2C"),
    frame("butter", "#FFE9A8", "#7A5B12"),
    frame("lavender", "#E3D9FF", "#4A3B7A"),
    frame("mint", "#CFEDDF", "#1F5C42"),
    frame("cherry", "#C6373F", "#FFFFFF"),
]

private func sampleFrame(_ code: String) -> Frame {
    sampleFrames.first { $0.code == code } ?? sampleFrames[0]
}

// MARK: - 그리기

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

private func composed(_ template: Template, _ frame: Frame, cuts: Int? = nil) -> UIImage {
    CutCompositor.render(CompositionRequest(
        images: numberedCuts(cuts ?? template.cutCount),
        template: template,
        frame: frame,
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

/* 템플릿 8종 전수. 0.1.0의 "컷 수 × 레이아웃 16조합"을 대체한다 — 조합이 아니라 목록이라
 * 서버가 템플릿을 늘리면 이 표본에 한 줄 추가하면 된다.
 *
 * 여기서 눈으로 확인할 것: 컷 번호가 왼쪽 위부터 행 우선인지, 캔버스 비율이 `aspectRatio`와
 * 맞는지(`strip4`는 세로로 길고 `strip4wide`는 가로로 길다), 거터가 이웃 사이에만 있고
 * 바깥 여백은 padding만큼인지. */
#Preview("템플릿 8종", traits: .sizeThatFitsLayout) {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.x4) {
            ForEach(sampleTemplates, id: \.code) { item in
                HStack(alignment: .top, spacing: Spacing.x3) {
                    labeled("\(item.code) · \(item.aspectRatio)",
                            composed(item, sampleFrame("white")))
                    labeled("basic", composed(item, sampleFrame("basic")))
                }
            }
        }
        .padding(Spacing.x4)
    }
}

#Preview("프레임 8종", traits: .sizeThatFitsLayout) {
    ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: Spacing.x3) {
            ForEach(sampleFrames, id: \.code) { frame in
                labeled(frame.code, composed(sampleTemplates[3], frame))
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
        labeled("basic 2/4", composed(sampleTemplates[3], sampleFrame("basic"), cuts: 2))
        labeled("white 2/4", composed(sampleTemplates[3], sampleFrame("white"), cuts: 2))
        labeled("cherry 2/4", composed(sampleTemplates[3], sampleFrame("cherry"), cuts: 2))
    }
    .padding(Spacing.x4)
}
#endif

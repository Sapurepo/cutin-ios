/* N컷 합성(베이킹) — 이 스파이크의 핵심.
 *
 * RN판(`cutFrame.tsx`)은 컷·프레임·필터를 **렌더 시점에 뷰 트리로** 그렸고 결과가 파일로 남지
 * 않았다. 여기서는 Core Graphics 캔버스에 실제로 구워 단일 JPEG로 만든다.
 * 서버 업로드·공유·사진 앱 저장이 전부 이 단계에 달려 있다. */

import UIKit

struct CompositionRequest: Sendable {
    var images: [UIImage]
    var count: CutCount
    var layout: CutLayout
    var skin: FrameSkin
    var filter: FilterID = .original
    /// 프레임 푸터 날짜 스탬프 — 스킨에 footer가 있을 때만 표시
    var stampDate: Date?
    /// 결과물 가로 픽셀. 프리뷰는 작게, 저장은 크게 부른다.
    var outputWidth: CGFloat = 1080
}

enum CutCompositor {
    /// 스킨 값(padding 12 / gutter 8 …)이 설계된 기준 폭. 출력 폭에 맞춰 비례 확대한다.
    private static let designWidth: CGFloat = 360

    /// 파일로 남기는 합성 폭. 화면용은 이보다 작게 굽는다(`ComposePreview`).
    static let saveWidth: CGFloat = 1080

    static func render(_ request: CompositionRequest) -> UIImage {
        let skin = request.skin
        let scale = request.outputWidth / designWidth
        let padding = skin.padding * scale
        let gutter = skin.gutter * scale
        let cellRadius = skin.cellRadius * scale
        let hasFooter = skin.footer == .logoDate

        // 컷 그리드는 항상 정사각 (원본 `styles.grid: { aspectRatio: 1 }`)
        let gridSide = request.outputWidth - padding * 2
        let footerHeight = hasFooter ? footerHeight(scale: scale) : 0
        let canvas = CGSize(width: request.outputWidth, height: padding * 2 + gridSide + footerHeight)

        let gridRect = CGRect(x: padding, y: padding, width: gridSide, height: gridSide)
        let cells = CutLayoutEngine.cells(count: request.count, layout: request.layout, in: gridRect, gutter: gutter)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            let cg = ctx.cgContext

            cg.setFillColor(UIColor(skin.bg).cgColor)
            cg.fill(CGRect(origin: .zero, size: canvas))

            // 빈 슬롯 표시 — 프레임 색에서 파생시킨다. 이전 구현은 잉크 팔레트를 역참조해
            // 흰 프레임 위에 검은 구멍이 뚫렸다.
            let slotFill = UIColor(skin.fg).withAlphaComponent(0.1).cgColor

            for (index, cell) in cells.enumerated() {
                cg.saveGState()
                UIBezierPath(roundedRect: cell, cornerRadius: cellRadius).addClip()
                cg.setFillColor(slotFill)
                cg.fill(cell)
                if index < request.images.count {
                    let source = request.images[index]
                    /* 필터는 원본 전체가 아니라 **이 셀에 실제로 그려질 크기**로 줄인 뒤 적용한다.
                     * 12MP 컷의 셀 안 크기는 프리뷰에서 30만 화소가 안 되므로 계산량이 그만큼 준다. */
                    let cut = ImageFilterer.apply(
                        request.filter,
                        to: source,
                        downsampledTo: drawnSize(of: source.size, in: cell)
                    )
                    draw(cut, aspectFillIn: cell)
                }
                cg.restoreGState()
            }

            if hasFooter {
                drawFooter(
                    skin: skin,
                    date: request.stampDate,
                    scale: scale,
                    in: CGRect(x: 0, y: padding + gridSide, width: canvas.width, height: footerHeight)
                )
            }
        }
    }

    // MARK: - 그리기 보조

    /// paddingTop 10 + 로고 라인 + gap 2 + 날짜 라인 (원본 `styles.footer`)
    private static func footerHeight(scale: CGFloat) -> CGFloat {
        (10 + 14 + 2 + 12) * scale
    }

    /// `contentFit: "cover"`로 셀을 채울 때 실제로 그려지는 크기.
    /// 필터 다운샘플 목표와 그리기가 **같은 식**을 써야 축소가 한 번만 일어난다.
    private static func drawnSize(of imageSize: CGSize, in rect: CGRect) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect.size }

        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// `contentFit: "cover"` 대응 — 비율 유지하며 셀을 꽉 채우고 넘치는 부분은 잘라낸다.
    private static func draw(_ image: UIImage, aspectFillIn rect: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }

        let size = drawnSize(of: image.size, in: rect)
        let origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        image.draw(in: CGRect(origin: origin, size: size))
    }

    private static func drawFooter(skin: FrameSkin, date: Date?, scale: CGFloat, in rect: CGRect) {
        let fg = UIColor(skin.fg)

        let logo = NSAttributedString(
            string: "CUTIN",
            attributes: [
                .font: UIFont(name: "Geist-SemiBold", size: 11 * scale)
                    ?? .systemFont(ofSize: 11 * scale, weight: .semibold),
                .foregroundColor: fg,
                .kern: 2 * scale,
            ]
        )
        let logoSize = logo.size()
        logo.draw(at: CGPoint(x: rect.midX - logoSize.width / 2, y: rect.minY + 10 * scale))

        guard let date else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        let stamp = NSAttributedString(
            string: formatter.string(from: date),
            attributes: [
                .font: UIFont(name: "Geist-Medium", size: 9 * scale)
                    ?? .systemFont(ofSize: 9 * scale, weight: .medium),
                .foregroundColor: fg.withAlphaComponent(0.65),
                .kern: 1 * scale,
            ]
        )
        let stampSize = stamp.size()
        stamp.draw(at: CGPoint(
            x: rect.midX - stampSize.width / 2,
            y: rect.minY + (10 + 14 + 2) * scale
        ))
    }
}

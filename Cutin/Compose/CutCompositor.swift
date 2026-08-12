/* N컷 합성(베이킹) — 이 스파이크의 핵심.
 *
 * RN판(`cutFrame.tsx`)은 컷·프레임·필터를 **렌더 시점에 뷰 트리로** 그렸고 결과가 파일로 남지
 * 않았다. 여기서는 Core Graphics 캔버스에 실제로 구워 단일 JPEG로 만든다.
 * 서버 업로드·공유·사진 앱 저장이 전부 이 단계에 달려 있다. */

import UIKit

struct CompositionRequest {
    var images: [UIImage]
    var count: CutCount
    var layout: CutLayout
    var skin: FrameSkin?
    var filter: FilterID = .original
    /// 프레임 푸터 날짜 스탬프 — 스킨에 footer가 있을 때만 표시
    var stampDate: Date?
    /// 결과물 가로 픽셀. 프리뷰는 작게, 저장은 크게 부른다.
    var outputWidth: CGFloat = 1080
}

enum CutCompositor {
    /// 스킨 값(padding 12 / gutter 8 …)이 설계된 기준 폭. 출력 폭에 맞춰 비례 확대한다.
    private static let designWidth: CGFloat = 360
    /// 기본 룩(스킨 없음)의 헤어라인 거터 — 원본 `cutFrame.tsx`의 `GUTTER`
    private static let defaultGutter: CGFloat = 4
    private static let defaultCellRadius: CGFloat = 3

    static func render(_ request: CompositionRequest) -> UIImage {
        let scale = request.outputWidth / designWidth
        let padding = (request.skin?.padding ?? defaultGutter) * scale
        let gutter = (request.skin?.gutter ?? defaultGutter) * scale
        let cellRadius = (request.skin?.cellRadius ?? defaultCellRadius) * scale
        let hasFooter = request.skin?.footer == .logoDate

        // 컷 그리드는 항상 정사각 (원본 `styles.grid: { aspectRatio: 1 }`)
        let gridSide = request.outputWidth - padding * 2
        let footerHeight = hasFooter ? footerHeight(scale: scale) : 0
        let canvas = CGSize(width: request.outputWidth, height: padding * 2 + gridSide + footerHeight)

        let gridRect = CGRect(x: padding, y: padding, width: gridSide, height: gridSide)
        let cells = CutLayoutEngine.cells(count: request.count, layout: request.layout, in: gridRect, gutter: gutter)

        let filtered = request.images.map { ImageFilterer.apply(request.filter, to: $0) }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            let cg = ctx.cgContext

            // 프레임 배경 — 스킨이 없으면 기본 룩(잉크 계열 sunken)
            let background = request.skin?.bg ?? Palette.dark.surfaceSunken
            cg.setFillColor(UIColor(background).cgColor)
            cg.fill(CGRect(origin: .zero, size: canvas))

            for (index, cell) in cells.enumerated() {
                // 빈 슬롯은 살짝 어두운 플레이스홀더로 남긴다 (컷을 덜 찍고 저장한 경우)
                cg.saveGState()
                UIBezierPath(roundedRect: cell, cornerRadius: cellRadius).addClip()
                cg.setFillColor(UIColor(Palette.dark.surface).cgColor)
                cg.fill(cell)
                if index < filtered.count {
                    draw(filtered[index], aspectFillIn: cell)
                }
                cg.restoreGState()
            }

            if hasFooter, let skin = request.skin {
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

    /// `contentFit: "cover"` 대응 — 비율 유지하며 셀을 꽉 채우고 넘치는 부분은 잘라낸다.
    private static func draw(_ image: UIImage, aspectFillIn rect: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }

        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
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

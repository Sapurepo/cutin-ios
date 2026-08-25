/* N컷 합성(베이킹) — 이 저장소의 핵심.
 *
 * RN판(`cutFrame.tsx`)은 컷·프레임·필터를 **렌더 시점에 뷰 트리로** 그렸고 결과가 파일로 남지
 * 않았다. 여기서는 Core Graphics 캔버스에 실제로 구워 단일 JPEG로 만든다.
 * 서버 업로드·공유·사진 앱 저장이 전부 이 단계에 달려 있다.
 *
 * **합성이 클라이언트 몫인 것은 계약이다.** 서버 `postSchema.composed`에 "iOS가 만든 합성본"이라고
 * 적혀 있다 — 서버는 결과 JPEG만 받고 다시 그리지 않는다.
 *
 * 0.1.0과 달리 배치(`Template`)와 외형(`Frame`)이 서버에서 온다. 이 파일은 그 둘을 좌표와
 * 색으로 바꿔 그리기만 한다. */

import UIKit

struct CompositionRequest: Sendable {
    var images: [UIImage]
    /// 컷 수와 배치. 서버가 소유한다.
    var template: Template
    /// 외형. 서버가 소유하되 **null일 수 있어**(`Post.frame`) 여기서는 이미 해소된 값을 받는다.
    var frame: Frame
    var filter: FilterID = .original
    /// 프레임 장식(그림). 합성기는 동기라 받아 둔 것을 실어 넘긴다 — `FrameDecorLoader`.
    var decor: FrameDecor = .none
    /// 프레임 푸터 날짜 스탬프 — 프레임에 footer가 있을 때만 표시
    var stampDate: Date?
    /// 결과물 가로 픽셀. 프리뷰는 작게, 저장은 크게 부른다.
    var outputWidth: CGFloat = 1080
}

enum CutCompositor {
    /* 푸터의 글자 크기·여백이 설계된 기준 폭. 프레임의 길이 값과 달리 푸터 치수는 계약에 없어
     * (서버는 `footer: 'logoDate'` 켜고 끄는 것만 안다) 여전히 이 상수를 쓴다. */
    private static let designWidth: CGFloat = 360

    /// 파일로 남기는 합성 폭. 화면용은 이보다 작게 굽는다(`ComposePreview`).
    static let saveWidth: CGFloat = 1080

    /* 장식 밴드가 차지하는 높이 — 캔버스 폭 대비 비율이다. 폭 1080 기준 190px·150px로,
     * `Scripts/frames/renderDecor.swift`가 굽는 스트립의 크기와 같다. 두 곳이 갈리면 장식이
     * 밴드에 맞춰 늘거나 줄어 비율이 뭉개진다. */
    private static let topBandRatio: CGFloat = 190.0 / 1080
    private static let bottomBandRatio: CGFloat = 150.0 / 1080

    static func render(_ request: CompositionRequest) -> UIImage {
        let frame = request.frame
        let width = request.outputWidth

        /* 프레임의 길이는 **캔버스 폭 대비 비율**이다(서버 시드가 360pt 기준 px을 폭으로 나눠
         * 담았다). 그래서 폭만 곱하면 어떤 출력 크기에서도 같은 그림이 나온다. */
        let padding = CGFloat(frame.padding) * width
        let gutter = CGFloat(frame.gutter) * width
        let cellRadius = CGFloat(frame.cellRadius) * width

        let scale = width / designWidth
        let hasFooter = frame.footer?.known == .logoDate
        /* 푸터도 **없어도 자리를 비운다.** 밴드와 같은 이유다 — 푸터 유무로 캔버스 길이가 갈리면
         * `basic`처럼 스탬프 없는 프레임만 규격이 달라진다. 그리는 것만 조건부다. */
        let footer = footerHeight(scale: scale)

        /* 장식은 **자기 자리를 갖는다.** 사진 위에 얹으면 어느 컷이든 얼굴 위로 하트가 걸리고,
         * 사진 모서리와 프레임이 어긋나 보인다(사용자 피드백 2026-08-25 — 포토매틱 스트립 참조).
         *
         *     [상단 밴드][padding][그리드][하단 밴드][푸터][padding]
         *
         * **장식이 없는 프레임도 같은 자리를 비운다.** 장식 있는 프레임만 캔버스가 길어지면, 같은
         * 컷을 찍어도 프레임을 바꾸는 순간 결과물 규격과 사진 크기가 달라진다 — 화면에서는 세로로
         * 긴 쪽이 높이에 맞춰 축소되어 가로까지 좁아 보인다(사용자 결정 2026-08-25).
         *
         * 그래서 밴드 높이가 그림이 아니라 **레이아웃 상수**다. 장식 그림은 이 비율에 맞춰
         * 그려져 있다(`Scripts/frames/README.md`). */
        let topBand = width * Self.topBandRatio
        let bottomBand = width * Self.bottomBandRatio

        /* 그리드 비율은 템플릿이 정한다. 0.1.0은 컷 수와 무관하게 정사각이었다
         * (원본 `styles.grid: { aspectRatio: 1 }`). 서버 계약: `aspectRatio`·`slots`는
         * **컷 그리드 영역 기준**이며 프레임 여백과 푸터를 포함하지 않는다. */
        let gridWidth = width - padding * 2
        let gridHeight = gridWidth * CutGeometry.heightPerWidth(request.template.aspectRatio)
        let canvas = CGSize(
            width: width,
            height: topBand + padding * 2 + gridHeight + bottomBand + footer
        )

        let gridRect = CGRect(x: padding, y: topBand + padding, width: gridWidth, height: gridHeight)
        let cells = CutGeometry.cells(request.template.slots, in: gridRect, gutter: gutter)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            let cg = ctx.cgContext

            cg.setFillColor(UIColor(hexString: frame.background).cgColor)
            cg.fill(CGRect(origin: .zero, size: canvas))

            if let pattern = request.decor.pattern {
                tile(pattern, scale: request.decor.patternScale, in: canvas)
            }

            // 빈 슬롯 표시 — 프레임 색에서 파생시킨다. 이전 구현은 잉크 팔레트를 역참조해
            // 흰 프레임 위에 검은 구멍이 뚫렸다.
            let slotFill = UIColor(hexString: frame.foreground).withAlphaComponent(0.1).cgColor

            for (index, cell) in cells.enumerated() where !cell.isEmpty {
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

            // 장식은 자기 밴드 안에만 그린다 — 컷과 겹치지 않는다.
            if let top = request.decor.top {
                top.draw(in: CGRect(x: 0, y: 0, width: width, height: topBand))
            }
            if let bottom = request.decor.bottom {
                bottom.draw(in: CGRect(x: 0, y: gridRect.maxY, width: width, height: bottomBand))
            }

            if hasFooter {
                drawFooter(
                    frame: frame,
                    date: request.stampDate,
                    scale: scale,
                    in: CGRect(
                        x: 0, y: gridRect.maxY + bottomBand, width: canvas.width, height: footer
                    )
                )
            }
        }
    }

    // MARK: - 장식

    /// 캔버스 폭에 맞춰 늘렸을 때의 높이. 폭 100%가 계약이라 좌우 여백은 그림이 갖는다.
    private static func stripHeight(of image: UIImage, width: CGFloat) -> CGFloat? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return width * image.size.height / image.size.width
    }

    /* 배경 타일. 캔버스를 넘는 부분은 렌더러가 잘라 낸다 — 딱 떨어지지 않는 폭에서 마지막 열이
     * 반쯤 잘리는 것이 타일의 정상 동작이라 맞춰 줄이지 않는다.
     *
     * 크기가 0이면 while이 끝나지 않는다. 서버 값이라 `assert`가 아니라 반환으로 막는다. */
    private static func tile(_ image: UIImage, scale: CGFloat, in canvas: CGSize) {
        let width = canvas.width * scale
        guard width > 0, let height = stripHeight(of: image, width: width), height > 0 else { return }

        var y: CGFloat = 0
        while y < canvas.height {
            var x: CGFloat = 0
            while x < canvas.width {
                image.draw(in: CGRect(x: x, y: y, width: width, height: height))
                x += width
            }
            y += height
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

    private static func drawFooter(frame: Frame, date: Date?, scale: CGFloat, in rect: CGRect) {
        let fg = UIColor(hexString: frame.foreground)

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

/* 서버가 색을 `"#RRGGBB"` 문자열로 준다. 0.1.0의 `Color(hex: UInt32)`는 소스에 박은 상수용이라
 * 문자열 경로가 없었다.
 *
 * 파싱 실패는 마젠타로 떨어진다 — 검정이나 흰색으로 폴백하면 "프레임 색이 왜 이러지"를
 * 눈으로 알아채기 어렵다. 있을 수 없는 색이어야 즉시 보인다. */
extension UIColor {
    convenience init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }

        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            self.init(red: 1, green: 0, blue: 1, alpha: 1)
            return
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

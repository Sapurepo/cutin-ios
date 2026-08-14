/* 임시 검증 하니스 — 앱 타깃에 넣어 한 번 돌리고 다시 뺀다.
 *
 * 이 브랜치에서 새로 생긴 계산을 검사한다:
 *   ① `CutGeometry.heightPerWidth` — `"W:H"` 파싱과 실패 폴백
 *   ② `CutGeometry.cells` — 슬롯 → 좌표, 거터가 **이웃 사이에만** 들어가는지
 *   ③ `CutGeometry.isRenderable` — 못 그리는 서버 시드를 거르는지 (음성 대조군 포함)
 *   ④ `CutCompositor.render` — 캔버스 크기가 `padding·aspectRatio·footer`에서 나오는지
 *   ⑤ 컷 순서 — `images[i]`가 `cells[i]`에 그려지는지 (**픽셀을 읽어** 확인한다)
 *
 * ⑤가 이 하니스의 이유다. 프리뷰에 컷 번호를 박아 두었지만 눈으로 보는 검사는 행 우선·열 우선
 * 뒤집힘을 놓치기 쉽고, 4컷 정사각에서는 두 배치가 비슷해 보인다.
 *
 * ## 서버 시드를 쓰지 않는 이유
 *
 * 여기 있는 템플릿·프레임은 **검사용으로 만든 값**이다(서버 시드 사본이 아니다). 검사 대상이
 * "이 슬롯 배열이 이 좌표로 펴지는가"라서 실제 시드 값이 필요하지 않고, 사본을 두면 내가
 * 옮겨 적은 값을 시험하게 된다. 서버가 준 값이 계약과 맞는지는 `Scripts/contract`가 본다.
 *
 * 실행: SIMCTL_CHILD_GEOMETRY_CHECK=1 로 앱을 띄우면 stdout에 결과를 뱉는다. */

#if DEBUG
import UIKit

/* `@MainActor`인 이유: 실패 수를 static으로 세는데 Swift 6에서 격리 없는 가변
 * 전역 상태는 금지된다. 부르는 곳(`CutinApp.init`)이 이미 메인 액터다. */
@MainActor
enum GeometryHarness {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["GEOMETRY_CHECK"] == "1"
    }

    private static var failures = 0

    static func run() {
        failures = 0
        checkAspectRatio()
        checkCells()
        checkRenderable()
        checkCanvas()
        checkCutOrder()
        print("=== 결과: \(failures == 0 ? "전부 통과" : "실패 \(failures)건") ===")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - 검사 보조

    private static func expect(_ passed: Bool, _ name: String, _ detail: String = "") {
        if passed {
            print("PASS  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)  \(detail)")
        }
    }

    /// 부동소수 비교. 좌표는 비율 곱셈을 거치므로 정확히 같기를 기대할 수 없다.
    private static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: - 표본 (검사용 · 서버 시드 사본이 아니다)

    private static let id = UUID()

    private static func grid(_ columns: Int, _ rows: Int) -> [TemplateSlot] {
        (0..<rows).flatMap { row in
            (0..<columns).map { column in
                TemplateSlot(
                    x: Double(column) / Double(columns), y: Double(row) / Double(rows),
                    width: 1 / Double(columns), height: 1 / Double(rows)
                )
            }
        }
    }

    private static func template(_ aspectRatio: String, _ slots: [TemplateSlot]) -> Template {
        Template(id: id, code: "t", name: "t", cutCount: slots.count,
                 aspectRatio: aspectRatio, slots: slots)
    }

    private static func frame(padding: Double, gutter: Double, footer: Bool) -> Frame {
        Frame(id: id, code: "f", name: "f", background: "#FFFFFF", foreground: "#000000",
              padding: padding, gutter: gutter, cellRadius: 0,
              footer: footer ? ServerEnum(.logoDate) : nil)
    }

    // MARK: - ① 비율 파싱

    private static func checkAspectRatio() {
        print("=== ① heightPerWidth ===")
        let cases: [(String, CGFloat)] = [
            ("3:4", 4.0 / 3), ("1:2", 2), ("2:1", 0.5), ("1:1", 1),
            ("1:3", 3), ("3:1", 1.0 / 3), ("2:3", 1.5),
        ]
        for (input, expected) in cases {
            let got = CutGeometry.heightPerWidth(input)
            expect(near(got, expected, 0.0001), "\(input) → \(expected)", "got \(got)")
        }
        /* 폴백은 1(정사각)이다. 서버가 새 표기를 쓰기 시작해도 비율만 어긋나고 화면은 뜬다.
         * 던지게 만들면 템플릿 하나 때문에 편집 화면 전체가 죽는다. */
        for bad in ["", "abc", "1", "0:1", "1:0", "1:-2", "1:2:3", "x:y"] {
            let got = CutGeometry.heightPerWidth(bad)
            expect(near(got, 1, 0.0001), "잘못된 표기 \"\(bad)\" → 1", "got \(got)")
        }
    }

    // MARK: - ② 슬롯 → 좌표

    private static func checkCells() {
        print("=== ② cells (거터는 이웃 사이에만) ===")
        let rect = CGRect(x: 12, y: 12, width: 336, height: 336)
        let gutter: CGFloat = 8

        for (columns, rows) in [(1, 1), (2, 2), (1, 4), (4, 1), (2, 3)] {
            let name = "grid(\(columns),\(rows))"
            let slots = grid(columns, rows)
            let cells = CutGeometry.cells(slots, in: rect, gutter: gutter)

            expect(cells.count == slots.count, "\(name) 셀 수", "\(cells.count)")

            // 바깥 경계는 그리드 사각형과 정확히 맞아야 한다 — 바깥 여백은 프레임 padding의 몫이다.
            let minX = cells.map(\.minX).min() ?? 0
            let maxX = cells.map(\.maxX).max() ?? 0
            let minY = cells.map(\.minY).min() ?? 0
            let maxY = cells.map(\.maxY).max() ?? 0
            expect(near(minX, rect.minX) && near(maxX, rect.maxX)
                   && near(minY, rect.minY) && near(maxY, rect.maxY),
                   "\(name) 바깥 경계 = 그리드",
                   "x[\(minX),\(maxX)] y[\(minY),\(maxY)] vs \(rect)")

            // 가로 이웃 간격 = 거터
            if columns > 1 {
                let gap = cells[1].minX - cells[0].maxX
                expect(near(gap, gutter), "\(name) 가로 이웃 간격 = \(gutter)", "got \(gap)")
            }
            // 세로 이웃 간격 = 거터
            if rows > 1 {
                let gap = cells[columns].minY - cells[0].maxY
                expect(near(gap, gutter), "\(name) 세로 이웃 간격 = \(gutter)", "got \(gap)")
            }
            // 겹침 0
            let overlapping = cells.indices.contains { i in
                cells[(i + 1)...].contains { !cells[i].intersection($0).isNull }
            }
            expect(!overlapping, "\(name) 겹침 없음")
        }

        /* 거터가 셀보다 크면 음수 크기가 나온다. 그리기 호출이 조용히 어긋나는 대신
         * `.zero`로 걸러 내는지 본다 — 합성기는 `isEmpty`인 셀을 건너뛴다. */
        let tiny = CutGeometry.cells(grid(4, 4), in: rect, gutter: 400)
        expect(tiny.allSatisfy { $0 == .zero }, "거터 > 셀 → .zero",
               "\(tiny.filter { $0 != .zero }.count)개가 남았다")
    }

    // MARK: - ③ 그릴 수 있는지 (음성 대조군)

    private static func checkRenderable() {
        print("=== ③ isRenderable ===")
        expect(CutGeometry.isRenderable(template("1:1", grid(2, 2))), "정상 격자 → true")

        // 서버 데이터가 잘못된 경우들. 크래시가 아니라 목록에서 빠져야 한다.
        let mismatched = Template(id: id, code: "t", name: "t", cutCount: 3,
                                  aspectRatio: "1:1", slots: grid(2, 2))
        expect(!CutGeometry.isRenderable(mismatched), "컷 수 ≠ 슬롯 수 → false")

        expect(!CutGeometry.isRenderable(template("1:1", [
            TemplateSlot(x: 0, y: 0, width: 1.5, height: 1),
        ])), "0~1 밖 → false")

        expect(!CutGeometry.isRenderable(template("1:1", [
            TemplateSlot(x: 0, y: 0, width: 0.6, height: 1),
            TemplateSlot(x: 0.4, y: 0, width: 0.6, height: 1),
        ])), "겹침 → false")

        expect(!CutGeometry.isRenderable(template("1:1", [
            TemplateSlot(x: 0, y: 0, width: 0, height: 1),
        ])), "면적 0 → false")

        expect(!CutGeometry.isRenderable(template("1:1", [])), "슬롯 없음 → false")

        // 맞물린 비격자 배치(빅 레프트 모양)도 통과해야 한다 — 격자만 받으면 안 된다.
        expect(CutGeometry.isRenderable(template("1:1", [
            TemplateSlot(x: 0, y: 0, width: 0.615385, height: 1),
            TemplateSlot(x: 0.615385, y: 0, width: 0.384615, height: 0.333333),
            TemplateSlot(x: 0.615385, y: 0.333333, width: 0.384615, height: 0.333333),
            TemplateSlot(x: 0.615385, y: 0.666667, width: 0.384615, height: 0.333334),
        ])), "비격자 맞물림 → true")
    }

    // MARK: - ④ 캔버스 크기

    private static func checkCanvas() {
        print("=== ④ 캔버스 크기 = padding·aspectRatio·footer ===")
        let width: CGFloat = 720
        let paddingRatio = 12.0 / 360
        let footerHeight = (10 + 14 + 2 + 12) * width / 360

        for (ratio, hpw) in [("3:4", 4.0 / 3), ("1:1", 1.0), ("1:3", 3.0), ("3:1", 1.0 / 3)] {
            for hasFooter in [false, true] {
                let skin = frame(padding: paddingRatio, gutter: 8.0 / 360, footer: hasFooter)
                let image = CutCompositor.render(CompositionRequest(
                    images: [], template: template(ratio, grid(2, 2)), frame: skin,
                    stampDate: Date(timeIntervalSince1970: 0), outputWidth: width
                ))
                let padding = CGFloat(paddingRatio) * width
                let expected = padding * 2 + (width - padding * 2) * CGFloat(hpw)
                    + (hasFooter ? footerHeight : 0)
                expect(near(image.size.width, width) && near(image.size.height, expected, 1),
                       "\(ratio) footer=\(hasFooter)",
                       "got \(image.size), expected (\(width), \(expected))")
            }
        }
    }

    // MARK: - ⑤ 컷 순서 (픽셀을 읽는다)

    /* `images[i]`가 `cells[i]`에 그려지는지. 행 우선·열 우선이 뒤집히면 4컷 정사각에서는
     * 눈으로 알아채기 어렵다 — 단색 컷을 넣고 셀 중심의 픽셀을 읽어 숫자로 확인한다. */
    private static func checkCutOrder() {
        print("=== ⑤ 컷 순서 (셀 중심 픽셀) ===")
        let colors: [(r: UInt8, g: UInt8, b: UInt8)] = [
            (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0), (255, 0, 255), (0, 255, 255),
        ]

        for (columns, rows) in [(2, 2), (1, 4), (4, 1), (2, 3)] {
            let slots = grid(columns, rows)
            let item = template("1:1", slots)
            let skin = frame(padding: 12.0 / 360, gutter: 8.0 / 360, footer: false)
            let width: CGFloat = 720

            let images = (0..<slots.count).map { solid(colors[$0]) }
            let composed = CutCompositor.render(CompositionRequest(
                images: images, template: item, frame: skin,
                stampDate: nil, outputWidth: width
            ))

            /* 셀 중심을 **`CutGeometry`를 쓰지 않고** 슬롯에서 직접 구한다. `CutGeometry.cells`로
             * 기대 좌표를 만들면 그 함수가 순서를 뒤집어도 기대값이 같이 뒤집혀 통과한다 —
             * 검사 대상이 "슬롯 i번이 컷 i번"이라는 대응이므로 기대값은 밖에서 와야 한다.
             * (거터는 셀을 대칭으로 줄이므로 중심을 옮기지 않는다.) */
            let padding = CGFloat(skin.padding) * width
            let gridWidth = width - padding * 2
            let inset = CGFloat(skin.gutter) * width / 2
            let outer = CGRect(x: padding, y: padding, width: gridWidth,
                               height: gridWidth * CutGeometry.heightPerWidth(item.aspectRatio))
                .insetBy(dx: -inset, dy: -inset)

            var mismatched: [Int] = []
            for (index, slot) in slots.enumerated() {
                let center = CGPoint(
                    x: outer.minX + CGFloat(slot.x + slot.width / 2) * outer.width,
                    y: outer.minY + CGFloat(slot.y + slot.height / 2) * outer.height
                )
                guard let pixel = pixel(in: composed, at: center)
                else { mismatched.append(index); continue }
                let want = colors[index]
                // JPEG가 아니라 비트맵을 직접 읽으므로 오차는 리샘플링뿐이다.
                let matches = abs(Int(pixel.0) - Int(want.r)) < 12
                    && abs(Int(pixel.1) - Int(want.g)) < 12
                    && abs(Int(pixel.2) - Int(want.b)) < 12
                if !matches { mismatched.append(index) }
            }
            expect(mismatched.isEmpty, "grid(\(columns),\(rows)) 컷 순서",
                   "어긋난 슬롯 \(mismatched)")
        }
    }

    private static func solid(_ color: (r: UInt8, g: UInt8, b: UInt8)) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format)
            .image { _ in
                UIColor(red: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                        blue: CGFloat(color.b) / 255, alpha: 1).setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: 200, height: 200))
            }
    }

    private static func pixel(in image: UIImage, at point: CGPoint) -> (UInt8, UInt8, UInt8)? {
        guard let cgImage = image.cgImage else { return nil }
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, y >= 0, x < cgImage.width, y < cgImage.height else { return nil }

        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: CGFloat(-x), y: CGFloat(y - cgImage.height + 1))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return (bytes[0], bytes[1], bytes[2])
    }
}
#endif

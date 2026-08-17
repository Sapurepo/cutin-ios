// 시드용 컷·합성본 생성 — 앱의 CutCompositor 규칙(프레임 padding/gutter/radius, 푸터)을 흉내낸다.
// 사용: swift compose.swift <spec.json> <srcDir> <outDir>
// spec: [{"id":"p1","template":"grid4","frame":"white","aspect":"1:1","slots":[{x,y,width,height}],
//         "padding":0.033,"gutter":0.022,"radius":0.0055,"bg":"#FFFFFF","fg":"#0A0A0B","footer":true,
//         "sources":["IMG_0001.JPG",...], "offsets":[0.1,0.5,...]}]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CoreText

struct Slot: Decodable { let x, y, width, height: Double }
struct Spec: Decodable {
    let id, template, aspect, bg, fg: String
    let slots: [Slot]
    let padding, gutter, radius: Double
    let footer: Bool
    let sources: [String]
    let offsets: [Double]
}

let args = CommandLine.arguments
let specs = try JSONDecoder().decode([Spec].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let srcDir = URL(fileURLWithPath: args[2]); let outDir = URL(fileURLWithPath: args[3])

func load(_ name: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(srcDir.appendingPathComponent(name) as CFURL, nil)!
    let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts)!
}
func color(_ hex: String) -> CGColor {
    var s = hex; s.removeFirst(); let v = UInt32(s, radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF)/255, green: CGFloat((v >> 8) & 0xFF)/255, blue: CGFloat(v & 0xFF)/255, alpha: 1)
}
func writeJPEG(_ img: CGImage, _ url: URL) {
    let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
    CGImageDestinationFinalize(dst)
}
/// 원본에서 aspect(w/h)의 영역을 offset(0~1, 긴 축 위치)으로 잘라 폭 w로 리사이즈
func crop(_ src: CGImage, aspect: CGFloat, offset: CGFloat, width w: Int) -> CGImage {
    let sw = CGFloat(src.width), sh = CGFloat(src.height)
    var cw = sw, ch = sw / aspect
    if ch > sh { ch = sh; cw = sh * aspect }
    let x = (sw - cw) * offset, y = (sh - ch) * (1 - offset)
    let cropped = src.cropping(to: CGRect(x: x, y: y, width: cw, height: ch))!
    let h = Int(CGFloat(w) / aspect)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}
func heightPerWidth(_ a: String) -> CGFloat { let p = a.split(separator: ":").map { CGFloat(Double($0)!) }; return p[1] / p[0] }

for spec in specs {
    let width: CGFloat = 1080
    let padding = spec.padding * width, gutter = spec.gutter * width, radius = spec.radius * width
    let gridW = width - padding * 2, gridH = gridW * heightPerWidth(spec.aspect)
    let footerH: CGFloat = spec.footer ? 26 * (width / 360) : 0
    let canvas = CGSize(width: width, height: padding * 2 + gridH + footerH)
    let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setFillColor(color(spec.bg)); ctx.fill(CGRect(origin: .zero, size: canvas))
    // CG는 원점이 좌하단 — 슬롯 y를 뒤집는다
    let inset = gutter / 2
    let outer = CGRect(x: padding, y: padding + footerH, width: gridW, height: gridH).insetBy(dx: -inset, dy: -inset)
    var cutImages: [CGImage] = []
    for (i, slot) in spec.slots.enumerated() {
        let cell = CGRect(x: outer.minX + slot.x * outer.width,
                          y: outer.minY + (1 - slot.y - slot.height) * outer.height,
                          width: slot.width * outer.width, height: slot.height * outer.height).insetBy(dx: inset, dy: inset)
        let src = load(spec.sources[i % spec.sources.count])
        let cut = crop(src, aspect: cell.width / cell.height, offset: CGFloat(spec.offsets[i % spec.offsets.count]), width: 900)
        cutImages.append(cut)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: cell, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
        ctx.draw(cut, in: cell)
        ctx.restoreGState()
    }
    if spec.footer {
        let scale = width / 360
        let attrs = [kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 9 * scale, nil), kCTForegroundColorAttributeName: color(spec.fg)] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "CUTIN" as CFString, attrs))
        ctx.textPosition = CGPoint(x: padding, y: padding + footerH * 0.35); CTLineDraw(line, ctx)
        let dattrs = [kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 8 * scale, nil), kCTForegroundColorAttributeName: color(spec.fg)] as CFDictionary
        let dline = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "2026.08.17" as CFString, dattrs))
        let dw = CTLineGetTypographicBounds(dline, nil, nil, nil)
        ctx.textPosition = CGPoint(x: width - padding - dw, y: padding + footerH * 0.35); CTLineDraw(dline, ctx)
    }
    let composed = ctx.makeImage()!
    let dir = outDir.appendingPathComponent(spec.id)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    writeJPEG(composed, dir.appendingPathComponent("composed.jpg"))
    for (i, cut) in cutImages.enumerated() { writeJPEG(cut, dir.appendingPathComponent("cut\(i).jpg")) }
    print("\(spec.id) \(Int(canvas.width))x\(Int(canvas.height)) cuts=\(cutImages.count)")
}

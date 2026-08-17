// 스크린샷 몽타주 — swift montage.swift <out.png> <cellWidth> <columns> <label=path>...
import Foundation
import CoreGraphics
import ImageIO
import CoreText
import UniformTypeIdentifiers

let args = CommandLine.arguments
let outPath = args[1]; let cellW = CGFloat(Double(args[2])!); let cols = Int(args[3])!
let items = args[4...].map { a -> (String, String) in let p = a.split(separator: "=", maxSplits: 1).map(String.init); return (p[0], p[1]) }
func load(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}
let images = items.map { ($0.0, load($0.1)) }
let ratio: CGFloat = 2622.0 / 1206.0
let cellH = cellW * ratio, labelH: CGFloat = 28, pad: CGFloat = 12
let rows = Int(ceil(Double(images.count) / Double(cols)))
let W = pad + CGFloat(cols) * (cellW + pad), H = pad + CGFloat(rows) * (cellH + labelH + pad)
let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
ctx.setFillColor(CGColor(gray: 0.93, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
ctx.interpolationQuality = .high
for (i, (label, img)) in images.enumerated() {
    let r = i / cols, c = i % cols
    let x = pad + CGFloat(c) * (cellW + pad)
    let yTop = pad + CGFloat(r) * (cellH + labelH + pad)
    let y = H - yTop - labelH - cellH   // CG 좌표
    if let img { ctx.draw(img, in: CGRect(x: x, y: y, width: cellW, height: cellH)) }
    let attrs = [kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 13, nil), kCTForegroundColorAttributeName: CGColor(gray: 0.15, alpha: 1)] as CFDictionary
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, label as CFString, attrs))
    ctx.textPosition = CGPoint(x: x, y: y + cellH + 8); CTLineDraw(line, ctx)
}
let out = ctx.makeImage()!
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, out, nil); CGImageDestinationFinalize(dst)
print("wrote \(outPath) \(Int(W))x\(Int(H))")

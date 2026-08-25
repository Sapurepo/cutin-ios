/* 프레임 장식 에셋 생성 — swift Scripts/frames/renderDecor.swift <outDir>
 *
 * 서버 `frames`가 갖는 장식 URL 3종(상단 스트립·하단 스트립·배경 패턴 타일)의 PNG를 굽는다.
 * 스트립은 **캔버스 폭 100%로 늘려 위/아래 가장자리에 앵커**되므로 폭 1080 기준으로 그린다.
 *
 * 손으로 그린 SVG를 쓰지 않는 이유: 이 저장소에는 SVG 변환기가 없고(rsvg·ImageMagick 부재),
 * `Scripts/audit/montage.swift`가 이미 CoreGraphics 스크립트로 이미지를 굽는 관행을 만들었다.
 *
 * 확인용 목업(`mock-<code>.png`)도 함께 굽는다 — 실제 합성 결과와 같은 순서로 그린다:
 * 배경 → 패턴 타일 → 컷 → 상단 스트립 → 하단 스트립 → 푸터. */

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/* 폭 1080 기준. 스트립 높이는 앱의 `CutCompositor.topBandRatio`·`bottomBandRatio`와 **같은 값**
 * 이어야 한다 — 갈리면 장식이 밴드에 맞춰 늘거나 줄어 비율이 뭉개진다. */
let canvasWidth: CGFloat = 1080
let topHeight: CGFloat = 190
let bottomHeight: CGFloat = 150
let tileSize: CGFloat = 180
/* 하단 스트립 안에서 장식이 앉는 높이 — 밴드 한가운데다.
 *
 * 스트립이 컷 위에 얹히던 동안에는 푸터 글자를 피해 아래로 몰아야 했지만, 이제 밴드가 컷과
 * 푸터 사이의 제 자리를 차지하므로 가운데가 곧 제자리다. */
let bottomAnchor: CGFloat = bottomHeight / 2

// MARK: - 기본기

func rgb(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    var h = hex
    if h.hasPrefix("#") { h.removeFirst() }
    let v = UInt32(h, radix: 16) ?? 0xFF00FF
    return CGColor(
        srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: alpha
    )
}

/// 원점 좌상단·y 아래로 증가(UIKit 좌표계)로 뒤집은 컨텍스트.
func makeContext(_ width: CGFloat, _ height: CGFloat) -> CGContext {
    let ctx = CGContext(
        data: nil, width: Int(width), height: Int(height),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    return ctx
}

func save(_ image: CGImage, to path: String) {
    let dst = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(dst, image, nil)
    CGImageDestinationFinalize(dst)
}

/* 뒤집어 둔 컨텍스트에 이미지를 **똑바로** 그린다. `ctx.draw`를 그냥 부르면 y축 반전이
 * 이미지에도 적용돼 상하가 뒤집힌다. */
func drawUpright(_ ctx: CGContext, _ image: CGImage, in rect: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

func stroke(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, _ width: CGFloat) {
    ctx.addPath(path)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.strokePath()
}

// MARK: - 모양

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(
        x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
    ), transform: nil)
}

/* 매개변수 하트 곡선. 베지어로 손수 맞추는 것보다 형태가 안정적이다.
 * 원곡선의 y는 위로 자라므로 여기서 뒤집어 rect 안으로 정규화한다. */
func heart(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let steps = 120
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let x = 16 * pow(sin(t), 3)
        let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
        let point = CGPoint(
            x: rect.midX + x / 16 * rect.width / 2,
            y: rect.midY - y / 17 * rect.height / 2
        )
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

/// 네 갈래 반짝임. 축 끝을 향해 오목하게 파인 곡선이라 별보다 가볍게 읽힌다.
func sparkle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let c = CGPoint(x: rect.midX, y: rect.midY)
    let rx = rect.width / 2, ry = rect.height / 2
    let waist: CGFloat = 0.18
    path.move(to: CGPoint(x: c.x, y: c.y - ry))
    path.addQuadCurve(to: CGPoint(x: c.x + rx, y: c.y), control: CGPoint(x: c.x + rx * waist, y: c.y - ry * waist))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + ry), control: CGPoint(x: c.x + rx * waist, y: c.y + ry * waist))
    path.addQuadCurve(to: CGPoint(x: c.x - rx, y: c.y), control: CGPoint(x: c.x - rx * waist, y: c.y + ry * waist))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - ry), control: CGPoint(x: c.x - rx * waist, y: c.y - ry * waist))
    path.closeSubpath()
    return path
}

/// 겹친 원들의 합집합. 같은 경로 안에 넣어 한 번에 채우면 이음매가 생기지 않는다.
func cloud(at center: CGPoint, width: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let unit = width / 5
    let bottom = center.y + unit * 1.2
    path.addPath(circle(CGPoint(x: center.x - unit * 1.4, y: bottom - unit * 1.05), unit * 1.05))
    path.addPath(circle(CGPoint(x: center.x, y: bottom - unit * 1.5), unit * 1.5))
    path.addPath(circle(CGPoint(x: center.x + unit * 1.5, y: bottom - unit * 1.15), unit * 1.15))
    path.addRect(CGRect(x: center.x - unit * 1.4, y: bottom - unit * 0.9, width: unit * 2.9, height: unit * 0.9))
    return path
}

func flower(at center: CGPoint, radius: CGFloat, petals: Int = 5) -> CGPath {
    let path = CGMutablePath()
    for index in 0..<petals {
        let angle = CGFloat(index) / CGFloat(petals) * 2 * .pi
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: angle)
            .translatedBy(x: 0, y: -radius * 0.62)
        let petal = CGRect(x: -radius * 0.36, y: -radius * 0.5, width: radius * 0.72, height: radius)
        path.addPath(CGPath(ellipseIn: petal, transform: nil), transform: transform)
    }
    return path
}

/// 곰 얼굴 — 귀 두 개와 머리. 눈·코는 세트 쪽에서 따로 얹는다.
func bearHead(at center: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addPath(circle(CGPoint(x: center.x - radius * 0.82, y: center.y - radius * 0.72), radius * 0.42))
    path.addPath(circle(CGPoint(x: center.x + radius * 0.82, y: center.y - radius * 0.72), radius * 0.42))
    path.addPath(circle(center, radius))
    return path
}

/// 리본 한 개 — 좌우 고리와 매듭.
/// 발바닥 — 패드와 그 위에 붙는 발가락 네 개.
func paw(at center: CGPoint, size: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addPath(CGPath(ellipseIn: CGRect(
        x: center.x - size * 0.45, y: center.y - size * 0.30,
        width: size * 0.90, height: size * 0.78
    ), transform: nil))
    for (offsetX, offsetY, radius) in [
        (-0.52, -0.44, 0.155), (-0.18, -0.66, 0.175), (0.18, -0.66, 0.175), (0.52, -0.44, 0.155),
    ] as [(CGFloat, CGFloat, CGFloat)] {
        path.addPath(circle(
            CGPoint(x: center.x + offsetX * size, y: center.y + offsetY * size), radius * size
        ))
    }
    return path
}

func ribbon(at center: CGPoint, width: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let w = width / 2, h = width * 0.42
    path.move(to: center)
    path.addCurve(
        to: CGPoint(x: center.x - w, y: center.y - h * 0.75),
        control1: CGPoint(x: center.x - w * 0.35, y: center.y - h * 0.9),
        control2: CGPoint(x: center.x - w * 0.9, y: center.y - h * 1.1)
    )
    path.addCurve(
        to: center,
        control1: CGPoint(x: center.x - w * 1.1, y: center.y + h * 0.5),
        control2: CGPoint(x: center.x - w * 0.35, y: center.y + h * 0.35)
    )
    path.move(to: center)
    path.addCurve(
        to: CGPoint(x: center.x + w, y: center.y - h * 0.75),
        control1: CGPoint(x: center.x + w * 0.35, y: center.y - h * 0.9),
        control2: CGPoint(x: center.x + w * 0.9, y: center.y - h * 1.1)
    )
    path.addCurve(
        to: center,
        control1: CGPoint(x: center.x + w * 1.1, y: center.y + h * 0.5),
        control2: CGPoint(x: center.x + w * 0.35, y: center.y + h * 0.35)
    )
    return path
}

/// 위 가장자리에 매달린 줄. 가운데가 늘어진 곡선이다.
func garland(from left: CGPoint, to right: CGPoint, sag: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: left)
    path.addQuadCurve(
        to: right,
        control: CGPoint(x: (left.x + right.x) / 2, y: max(left.y, right.y) + sag * 2)
    )
    return path
}

/// 곡선 위 t 지점의 y — 매달린 장식을 줄에 붙이려고 쓴다.
func sagY(_ t: CGFloat, base: CGFloat, sag: CGFloat) -> CGFloat {
    base + 2 * sag * t * (1 - t) * 2
}

// MARK: - 세트

struct Decor {
    let code: String
    let name: String
    /// 목업에 쓰는 프레임 색 — 서버 시드에 그대로 넣을 값이다.
    let background: String
    let foreground: String
    let top: (CGContext) -> Void
    let bottom: (CGContext) -> Void
    /// nil이면 패턴 없는 프레임이다.
    let pattern: ((CGContext) -> Void)?
}

let decors: [Decor] = [
    Decor(
        code: "heart", name: "하트", background: "#FFE7EF", foreground: "#C2436B",
        top: { ctx in
            let accent = rgb("#FF6F91"), soft = rgb("#FFB3C8")
            let base: CGFloat = 34, sag: CGFloat = 30
            stroke(ctx, garland(from: CGPoint(x: -10, y: base), to: CGPoint(x: canvasWidth + 10, y: base), sag: sag), soft, 7)
            let spots: [(CGFloat, CGFloat, Bool)] = [(0.10, 70, false), (0.27, 96, true), (0.45, 78, false), (0.63, 100, true), (0.81, 72, false), (0.94, 86, true)]
            for (t, size, isAccent) in spots {
                let x = t * canvasWidth
                let y = sagY(t, base: base, sag: sag)
                stroke(ctx, {
                    let p = CGMutablePath(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + size * 0.34)); return p
                }(), soft, 5)
                fill(ctx, heart(in: CGRect(x: x - size / 2, y: y + size * 0.3, width: size, height: size * 0.92)), isAccent ? accent : soft)
            }
        },
        bottom: { ctx in
            let accent = rgb("#FF6F91"), soft = rgb("#FFB3C8")
            let y = bottomAnchor
            for (t, size, isAccent) in [
                (0.16, 64.0, false), (0.5, 92.0, true), (0.84, 64.0, false),
            ] as [(CGFloat, CGFloat, Bool)] {
                fill(ctx, heart(in: CGRect(x: t * canvasWidth - size / 2, y: y - size / 2,
                                           width: size, height: size * 0.92)),
                     isAccent ? accent : soft)
            }
            for step in 0..<8 {
                let x = canvasWidth * 0.24 + CGFloat(step) * 22
                fill(ctx, circle(CGPoint(x: x, y: y), 5), soft)
                fill(ctx, circle(CGPoint(x: canvasWidth - x, y: y), 5), soft)
            }
        },
        pattern: { ctx in
            let soft = rgb("#FFC9D8")
            fill(ctx, heart(in: CGRect(x: tileSize * 0.2, y: tileSize * 0.2, width: 40, height: 37)), soft)
            fill(ctx, circle(CGPoint(x: tileSize * 0.72, y: tileSize * 0.7), 7), soft)
        }
    ),
    Decor(
        code: "sparkle", name: "반짝", background: "#F3EAFF", foreground: "#5B3E96",
        top: { ctx in
            let accent = rgb("#8B5CF6"), soft = rgb("#C9B4F5"), pale = rgb("#E4D8FF")
            let spots: [(CGFloat, CGFloat, CGFloat, CGColor)] = [
                (0.07, 46, 110, soft), (0.17, 96, 62, accent), (0.30, 54, 128, pale),
                (0.44, 74, 48, soft), (0.55, 118, 96, accent), (0.68, 50, 44, pale),
                (0.79, 88, 122, soft), (0.90, 60, 56, accent), (0.97, 40, 112, pale),
            ]
            for (t, size, y, color) in spots {
                fill(ctx, sparkle(in: CGRect(x: t * canvasWidth - size / 2, y: y - size / 2, width: size, height: size * 1.25)), color)
            }
        },
        bottom: { ctx in
            let accent = rgb("#8B5CF6"), soft = rgb("#C9B4F5")
            let y = bottomAnchor
            for (t, size, isAccent) in [
                (0.16, 44.0, false), (0.29, 58.0, false), (0.5, 80.0, true),
                (0.71, 58.0, false), (0.84, 44.0, false),
            ] as [(CGFloat, CGFloat, Bool)] {
                fill(ctx, sparkle(in: CGRect(x: t * canvasWidth - size / 2, y: y - size / 2,
                                             width: size, height: size * 1.25)),
                     isAccent ? accent : soft)
            }
        },
        pattern: nil
    ),
    Decor(
        code: "cloud", name: "구름", background: "#DDEEFF", foreground: "#2F5D8C",
        top: { ctx in
            let white = rgb("#FFFFFF"), soft = rgb("#B7D9FA")
            fill(ctx, cloud(at: CGPoint(x: canvasWidth * 0.19, y: 96), width: 240), soft)
            fill(ctx, cloud(at: CGPoint(x: canvasWidth * 0.81, y: 92), width: 220), soft)
            fill(ctx, cloud(at: CGPoint(x: canvasWidth * 0.5, y: 108), width: 290), white)
        },
        bottom: { ctx in
            let white = rgb("#FFFFFF"), soft = rgb("#B7D9FA")
            fill(ctx, cloud(at: CGPoint(x: canvasWidth * 0.15, y: 96), width: 240), soft)
            fill(ctx, cloud(at: CGPoint(x: canvasWidth * 0.85, y: 92), width: 260), white)
        },
        pattern: nil
    ),
    Decor(
        code: "daisy", name: "데이지", background: "#EDF6E3", foreground: "#3F6B39",
        top: { ctx in
            let leaf = rgb("#8FC17A"), white = rgb("#FFFFFF"), yolk = rgb("#FFD84D")
            let base: CGFloat = 34, sag: CGFloat = 24
            stroke(ctx, garland(from: CGPoint(x: -10, y: base), to: CGPoint(x: canvasWidth + 10, y: base), sag: sag), leaf, 6)
            for (t, radius) in [(0.12, 46), (0.31, 62), (0.5, 50), (0.69, 66), (0.88, 44)] as [(CGFloat, CGFloat)] {
                let x = t * canvasWidth
                let line = sagY(t, base: base, sag: sag)
                let y = line + radius * 0.9
                stroke(ctx, {
                    let p = CGMutablePath(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: line)); return p
                }(), leaf, 5)
                fill(ctx, flower(at: CGPoint(x: x, y: y), radius: radius), white)
                fill(ctx, circle(CGPoint(x: x, y: y), radius * 0.3), yolk)
            }
        },
        bottom: { ctx in
            let leaf = rgb("#8FC17A"), white = rgb("#FFFFFF"), yolk = rgb("#FFD84D")
            let y = bottomAnchor
            stroke(ctx, garland(from: CGPoint(x: canvasWidth * 0.08, y: y - 10),
                                to: CGPoint(x: canvasWidth * 0.92, y: y - 10), sag: 14), leaf, 5)
            for (t, radius) in [(0.18, 40), (0.5, 50), (0.82, 40)] as [(CGFloat, CGFloat)] {
                let x = t * canvasWidth
                fill(ctx, flower(at: CGPoint(x: x, y: y), radius: radius), white)
                fill(ctx, circle(CGPoint(x: x, y: y), radius * 0.3), yolk)
            }
        },
        pattern: { ctx in
            let leaf = rgb("#B9DCA8")
            fill(ctx, flower(at: CGPoint(x: tileSize * 0.3, y: tileSize * 0.3), radius: 22), leaf)
            fill(ctx, circle(CGPoint(x: tileSize * 0.75, y: tileSize * 0.72), 6), leaf)
        }
    ),
    Decor(
        code: "bear", name: "곰돌이", background: "#F7E9D6", foreground: "#7A4A28",
        top: { ctx in
            let fur = rgb("#C08A5B"), dark = rgb("#7A4A28"), inner = rgb("#E8C3A0")
            let center = CGPoint(x: canvasWidth * 0.5, y: 92)
            let radius: CGFloat = 76
            fill(ctx, bearHead(at: center, radius: radius), fur)
            fill(ctx, circle(CGPoint(x: center.x - radius * 0.82, y: center.y - radius * 0.72), radius * 0.2), inner)
            fill(ctx, circle(CGPoint(x: center.x + radius * 0.82, y: center.y - radius * 0.72), radius * 0.2), inner)
            fill(ctx, CGPath(ellipseIn: CGRect(x: center.x - radius * 0.42, y: center.y + radius * 0.05, width: radius * 0.84, height: radius * 0.62), transform: nil), inner)
            fill(ctx, circle(CGPoint(x: center.x - radius * 0.36, y: center.y - radius * 0.12), 9), dark)
            fill(ctx, circle(CGPoint(x: center.x + radius * 0.36, y: center.y - radius * 0.12), 9), dark)
            fill(ctx, CGPath(ellipseIn: CGRect(x: center.x - 14, y: center.y + radius * 0.16, width: 28, height: 20), transform: nil), dark)
            for t in [0.13, 0.87] as [CGFloat] {
                fill(ctx, paw(at: CGPoint(x: t * canvasWidth, y: 92), size: 84), fur)
            }
        },
        bottom: { ctx in
            let fur = rgb("#C08A5B")
            for (t, size) in [(0.2, 64), (0.5, 80), (0.8, 64)] as [(CGFloat, CGFloat)] {
                fill(ctx, paw(at: CGPoint(x: t * canvasWidth, y: bottomAnchor), size: size), fur)
            }
        },
        pattern: nil
    ),
    Decor(
        code: "ribbon", name: "리본", background: "#FFF1F3", foreground: "#A03A54",
        top: { ctx in
            let accent = rgb("#E8657F"), soft = rgb("#F7B3C0"), knot = rgb("#C94A64")
            let y: CGFloat = 86
            stroke(ctx, {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 0, y: y + 6))
                p.addQuadCurve(to: CGPoint(x: canvasWidth * 0.5, y: y + 22), control: CGPoint(x: canvasWidth * 0.25, y: y - 16))
                p.addQuadCurve(to: CGPoint(x: canvasWidth, y: y + 6), control: CGPoint(x: canvasWidth * 0.75, y: y - 16))
                return p
            }(), soft, 16)
            fill(ctx, ribbon(at: CGPoint(x: canvasWidth * 0.5, y: y + 24), width: 260), accent)
            fill(ctx, CGPath(roundedRect: CGRect(x: canvasWidth * 0.5 - 26, y: y + 6, width: 52, height: 44), cornerWidth: 16, cornerHeight: 16, transform: nil), knot)
            for t in [0.14, 0.86] as [CGFloat] {
                fill(ctx, ribbon(at: CGPoint(x: t * canvasWidth, y: y - 6), width: 120), soft)
            }
        },
        bottom: { ctx in
            let accent = rgb("#E8657F"), soft = rgb("#F7B3C0")
            let y = bottomAnchor
            fill(ctx, ribbon(at: CGPoint(x: canvasWidth * 0.5, y: y), width: 140), accent)
            for t in [0.2, 0.8] as [CGFloat] {
                fill(ctx, ribbon(at: CGPoint(x: t * canvasWidth, y: y + 6), width: 92), soft)
            }
        },
        pattern: { ctx in
            let soft = rgb("#FBD3DB")
            for point in [CGPoint(x: tileSize * 0.25, y: tileSize * 0.25), CGPoint(x: tileSize * 0.75, y: tileSize * 0.75)] {
                fill(ctx, circle(point, 9), soft)
            }
        }
    ),
]

// MARK: - 목업

/* 확인용 목업. **앱의 `CutCompositor.render`와 같은 식이어야 한다** — 한번은 여기서 그리드 아래
 * 여백과 푸터 높이를 빠뜨렸다가, 하단 장식이 실기기에서만 CUTIN 스탬프를 덮었다.
 *
 *   canvas = 상단 밴드 + padding + grid + padding + 하단 밴드 + footer
 *   footer = (10 + 14 + 2 + 12) × (폭 / 360)      ← 푸터 치수만 360pt 설계 폭 기준이다
 *
 * 값은 서버 시드의 `decorated` 프레임과 같다 — 여백은 `standard`를 그대로 쓰고(단색 프레임과
 * 사진 크기가 같아야 한다) 거터·라운딩만 0이다. 밴드는 장식 유무와 무관하게 늘 자리를 가지므로
 * 단색 프레임의 캔버스도 이 목업과 같은 크기다. */
func mock(_ decor: Decor, top: CGImage, bottom: CGImage, pattern: CGImage?) -> CGImage {
    let padding = canvasWidth * (12.0 / 360)
    let gutter: CGFloat = 0
    let radius: CGFloat = 0
    let gridSide = canvasWidth - padding * 2
    let grid = CGRect(x: padding, y: topHeight + padding, width: gridSide, height: gridSide)
    let scale = canvasWidth / 360
    let footer = (10 + 14 + 2 + 12) * scale
    let height = grid.maxY + padding + bottomHeight + footer
    let ctx = makeContext(canvasWidth, height)

    ctx.setFillColor(rgb(decor.background))
    ctx.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: height))

    if let pattern {
        var y: CGFloat = 0
        while y < height {
            var x: CGFloat = 0
            while x < canvasWidth {
                drawUpright(ctx, pattern, in: CGRect(x: x, y: y, width: tileSize, height: tileSize))
                x += tileSize
            }
            y += tileSize
        }
    }

    let cellWidth = (grid.width - gutter) / 2
    for index in 0..<4 {
        let cell = CGRect(
            x: grid.minX + CGFloat(index % 2) * (cellWidth + gutter),
            y: grid.minY + CGFloat(index / 2) * (cellWidth + gutter),
            width: cellWidth, height: cellWidth
        )
        fill(ctx, CGPath(roundedRect: cell, cornerWidth: radius, cornerHeight: radius, transform: nil), CGColor(gray: 0.72 - CGFloat(index) * 0.05, alpha: 1))
    }

    drawUpright(ctx, top, in: CGRect(x: 0, y: 0, width: canvasWidth, height: topHeight))
    drawUpright(ctx, bottom, in: CGRect(x: 0, y: grid.maxY, width: canvasWidth, height: bottomHeight))

    // 푸터 — 합성기와 같은 자리(로고 +10, 날짜 +26, 설계 폭 360 기준).
    let footerTop = grid.maxY + bottomHeight
    drawFooterLine("CUTIN", size: 11 * scale, kern: 2 * scale, color: rgb(decor.foreground),
                   at: footerTop + 10 * scale, in: ctx, canvasHeight: height)
    drawFooterLine("2026.08.25", size: 9 * scale, kern: 1 * scale,
                   color: rgb(decor.foreground, 0.65),
                   at: footerTop + 26 * scale, in: ctx, canvasHeight: height)

    return ctx.makeImage()!
}

/// 뒤집어 둔 컨텍스트에 한 줄을 그린다. `y`는 글자 상자의 위쪽이다(합성기와 같은 기준).
func drawFooterLine(_ text: String, size: CGFloat, kern: CGFloat, color: CGColor,
                    at y: CGFloat, in ctx: CGContext, canvasHeight: CGFloat) {
    let attrs = [
        kCTFontAttributeName: CTFontCreateWithName("AvenirNext-DemiBold" as CFString, size, nil),
        kCTForegroundColorAttributeName: color,
        kCTKernAttributeName: kern as CFNumber,
    ] as CFDictionary
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs))
    let bounds = CTLineGetBoundsWithOptions(line, [])

    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: 0, y: canvasHeight)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = CGPoint(x: (canvasWidth - bounds.width) / 2, y: canvasHeight - y - size)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// MARK: - 실행

/* 첫 인자는 배포되는 자산이 놓일 곳(cutin-backend의 `assets/frames`), 둘째 인자는 확인용 목업을
 * 둘 곳이다. 목업을 자산 폴더에 섞으면 그대로 서버에 올라가므로 기본값도 하위 폴더로 가른다. */
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./out"
let mockDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "\(outDir)/mock"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(atPath: mockDir, withIntermediateDirectories: true)

for decor in decors {
    let topCtx = makeContext(canvasWidth, topHeight)
    decor.top(topCtx)
    let topImage = topCtx.makeImage()!
    save(topImage, to: "\(outDir)/\(decor.code)-top.png")

    let bottomCtx = makeContext(canvasWidth, bottomHeight)
    decor.bottom(bottomCtx)
    let bottomImage = bottomCtx.makeImage()!
    save(bottomImage, to: "\(outDir)/\(decor.code)-bottom.png")

    var patternImage: CGImage?
    if let draw = decor.pattern {
        let patternCtx = makeContext(tileSize, tileSize)
        draw(patternCtx)
        patternImage = patternCtx.makeImage()!
        save(patternImage!, to: "\(outDir)/\(decor.code)-pattern.png")
    }

    save(mock(decor, top: topImage, bottom: bottomImage, pattern: patternImage), to: "\(mockDir)/\(decor.code).png")
    print("\(decor.code) (\(decor.name)) — 완료")
}

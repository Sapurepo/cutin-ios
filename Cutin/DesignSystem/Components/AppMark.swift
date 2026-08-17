/* 앱 마크 — 아이콘의 꽃잎 넷(`AppIcon.icon`)을 SwiftUI로 그린다. 인트로가 한 장씩 피워 올린다.
 *
 * 아이콘 문서(`AppIcon.icon/icon.json` + `Assets/petal-*.svg`)와 **같은 좌표·같은 색**이다 —
 * 1024 캔버스의 SVG 경로를 그대로 옮기고, 문서의 레이어 이동값(points)을 더한다. 아이콘을
 * 다시 뽑으면 이 값들도 같이 바꾼다. 유리(glass)·반사는 흉내내지 않고 반투명 겹침만 남겼다 —
 * 겹치는 곳에서 색이 섞이는 것이 이 마크의 인상이고, 그건 불투명도만으로 난다. */

import SwiftUI

struct AppMark {
    struct Petal: Identifiable {
        let id: Int
        let color: Color
        /// 1024 캔버스에서의 이동값(문서의 translation-in-points).
        let offset: CGSize
    }

    /// 그리는 순서 = 인트로가 피우는 순서(위 → 오른쪽 → 아래 → 왼쪽, 아이콘 레이어 순).
    static let petals: [Petal] = [
        Petal(id: 0, color: Color(.sRGB, red: 0.49804, green: 0.69804, blue: 1.0), offset: CGSize(width: 0, height: -17.17)),
        Petal(id: 1, color: Color(.sRGB, red: 0.66275, green: 0.54902, blue: 1.0), offset: CGSize(width: 32.48, height: 0)),
        Petal(id: 2, color: Color(.sRGB, red: 0.78039, green: 0.60784, blue: 1.0), offset: CGSize(width: 0, height: 23.19)),
        Petal(id: 3, color: Color(.sRGB, red: 0.43137, green: 0.56078, blue: 0.96078), offset: CGSize(width: -22.74, height: 0)),
    ]

    /* 꽃잎 하나의 모양 — 위 꽃잎의 SVG(`petal-top.svg`)를 1024 캔버스 기준으로 옮긴 것.
     * 나머지 셋은 같은 모양을 중심(512,512) 둘레로 138씩 옮긴 것이라 이 경로 하나로 충분하다. */
    static func petalPath(in rect: CGRect) -> Path {
        let s = rect.width / 1024
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        // 중심이 (512,512)가 되도록 petal-top(중심 512,374)을 138 내린 좌표.
        path.move(to: p(512, 260))
        path.addCurve(to: p(764, 512), control1: p(625.4, 260), control2: p(764, 398.6))
        path.addCurve(to: p(512, 764), control1: p(764, 625.4), control2: p(625.4, 764))
        path.addCurve(to: p(260, 512), control1: p(398.6, 764), control2: p(260, 625.4))
        path.addCurve(to: p(512, 260), control1: p(260, 398.6), control2: p(398.6, 260))
        path.closeSubpath()
        return path
    }

    /// 꽃잎의 중심 위치(1024 캔버스, 이동값 포함) — 위/오른쪽/아래/왼쪽.
    static func center(of petal: Petal) -> CGPoint {
        let base: [CGPoint] = [CGPoint(x: 512, y: 374), CGPoint(x: 650, y: 512),
                               CGPoint(x: 512, y: 650), CGPoint(x: 374, y: 512)]
        let b = base[petal.id]
        return CGPoint(x: b.x + petal.offset.width, y: b.y + petal.offset.height)
    }
}

/// 꽃잎 하나 — 캔버스 크기(`size`)에 맞춰 자리와 크기를 잡는다. 인트로가 하나씩 애니메이션한다.
struct AppMarkPetal: View {
    let petal: AppMark.Petal
    /// 마크 전체(1024 캔버스)의 표시 크기
    let size: CGFloat

    var body: some View {
        let s = size / 1024
        let c = AppMark.center(of: petal)
        AppMark.petalPath(in: CGRect(x: 0, y: 0, width: size, height: size))
            .fill(petal.color)
            .opacity(0.82)
            .frame(width: size, height: size)
            // 경로는 중심(512,512)에 그려져 있다 — 꽃잎의 자리로 옮긴다.
            .offset(x: (c.x - 512) * s, y: (c.y - 512) * s)
    }
}

/// 마크 전체 — 카탈로그·프리뷰용.
struct AppMarkView: View {
    var size: CGFloat = 96
    var body: some View {
        ZStack {
            ForEach(AppMark.petals) { petal in
                AppMarkPetal(petal: petal, size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview("AppMark", traits: .sizeThatFitsLayout) {
    HStack(spacing: 24) {
        AppMarkView(size: 96)
        AppMarkView(size: 160)
    }
    .padding(24)
    .background(Palette.light.bg)
}

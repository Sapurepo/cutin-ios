/* 네컷 스트립 일러스트 — 로그인 히어로와 서비스 팁 세 장이 쓴다(호출부 2곳).
 *
 * 사진 없이 "이 앱이 만드는 물건"을 보여준다. 로그인 전에는 서버 템플릿·프레임을 받을 수 없고
 * 사진을 번들하면 남의 사진으로 첫인상을 만드는 셈이라, **합성기가 그리는 것과 같은 비례**
 * (프레임 여백·컷 간격·모서리·푸터)로 빈 스트립을 그린다. 슬롯은 옅은 그라데이션 —
 * "여기에 사진이 온다"를 말하되 사진인 척하지 않는다.
 *
 * 프레임 색은 서버 시드의 white·peach·lavender·butter 값을 그대로 쓴다. 장식이라 서버에서
 * 받지 않는다 — 서버가 프레임을 바꿔도 이 그림이 틀리는 것은 아니다. */

import SwiftUI

struct StripArt: View {
    enum Layout { case strip4, grid4 }
    struct Skin {
        let background: Color
        let foreground: Color
        static let white = Skin(background: Color(hex: 0xFFFFFF), foreground: Color(hex: 0x0A0A0B))
        static let peach = Skin(background: Color(hex: 0xFFD9CF), foreground: Color(hex: 0x8A3B2C))
        static let lavender = Skin(background: Color(hex: 0xE3D9FF), foreground: Color(hex: 0x4A3B7A))
        static let butter = Skin(background: Color(hex: 0xFFE9A8), foreground: Color(hex: 0x7A5B12))
    }

    var layout: Layout = .strip4
    var skin: Skin = .white
    var width: CGFloat = 120
    /// 채운 슬롯 수 — 팁 1장("찍는 중")처럼 앞 몇 칸만 채워 진행을 보여줄 때.
    var filled: Int? = nil

    /* 서버 프레임 시드의 비율(360pt 기준 px ÷ 360)을 그대로 — 합성기와 같은 그림이 나온다. */
    private var padding: CGFloat { width * 0.0333 }
    private var gutter: CGFloat { width * 0.0222 }
    private var radius: CGFloat { width * 0.0056 }
    private var footer: CGFloat { width * 0.072 }

    private var slots: [CGRect] {
        switch layout {
        case .strip4: return (0..<4).map { CGRect(x: 0, y: CGFloat($0) * 0.25, width: 1, height: 0.25) }
        case .grid4: return [CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                             CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
        }
    }
    private var gridAspect: CGFloat { layout == .strip4 ? 3 : 1 }   // 높이 ÷ 너비

    var body: some View {
        let gridW = width - padding * 2
        let gridH = gridW * gridAspect
        let height = padding * 2 + gridH + footer
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: width * 0.02)
                .fill(skin.background)
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                let inset = gutter / 2
                let cell = CGRect(x: padding - inset + slot.minX * (gridW + gutter),
                                  y: padding - inset + slot.minY * (gridH + gutter),
                                  width: slot.width * (gridW + gutter), height: slot.height * (gridH + gutter))
                    .insetBy(dx: inset, dy: inset)
                RoundedRectangle(cornerRadius: radius)
                    .fill(slotFill(index))
                    .frame(width: cell.width, height: cell.height)
                    .offset(x: cell.minX, y: cell.minY)
            }
            HStack {
                Text("CUTIN").font(Typography.logo(size: width * 0.05)).kerning(width * 0.05 * Typography.logoKerning)
                Spacer()
                Text("2026.08.17").font(Typography.font(.latin, .regular, size: width * 0.04))
            }
            .foregroundStyle(skin.foreground)
            .padding(.horizontal, padding)
            .frame(width: width, height: footer)
            .offset(y: padding + gridH + padding * 0.2)
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: width * 0.02))
        .accessibilityHidden(true)
    }

    private func slotFill(_ index: Int) -> AnyShapeStyle {
        if let filled, index >= filled {
            return AnyShapeStyle(skin.foreground.opacity(0.08))
        }
        // 사진 자리 — 위가 밝고 아래가 어두운 옅은 회색. 사진인 척하지 않으면서 비어 보이지 않게.
        return AnyShapeStyle(LinearGradient(
            colors: [skin.foreground.opacity(0.14), skin.foreground.opacity(0.32)],
            startPoint: .top, endPoint: .bottom))
    }
}

#Preview("StripArt", traits: .sizeThatFitsLayout) {
    HStack(spacing: 24) {
        StripArt(layout: .strip4, skin: .white, width: 110)
        StripArt(layout: .strip4, skin: .peach, width: 110, filled: 2)
        StripArt(layout: .grid4, skin: .lavender, width: 160)
    }
    .padding(24)
    .background(Palette.light.bg)
}

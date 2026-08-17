/* CUTIN 디자인 토큰 — cutin-frontend `packages/tokens`에서 이식한 모노크롬 골격.
 *
 * 규칙: 크롬(배경·표면·글·CTA·탭바)은 잉크/오프화이트 tone-on-tone. 위계는 FILL/OUTLINE/WEIGHT/SIZE로
 * 만들고 hue로 만들지 않는다. **"지금 켜져 있는 것"(고른 칩 · 내 반응 · 미읽음 점 · 핀 배지)은
 * 채움이 아니라 옅은 면 + 잉크 테두리 + 굵은 글씨**로 가른다 — 0.3.0의 검정 채움 칩이 CTA와 같은
 * 무게로 보이던 문제(감사 G1)를 색이 아니라 무게로 푼다. 0.4.0 초안은 여기에 웜 포인트 한 색을
 * 얹었다가 사용자 결정으로 잉크로 되돌렸다(`Design/README.md` 2026-08-17). `brand*` 토큰 이름은
 * 남겨 두었다 — 켜진 것의 색을 한 곳에서 바꾸는 손잡이라서다.
 * 순수 #000/#FFF는 눈부심·OLED 잔상 방지를 위해 의도적으로 피한다. */

import SwiftUI

// MARK: - Color scheme

struct Palette {
    let bg: Color
    let surface: Color
    let surfaceSunken: Color
    let border: Color
    let borderStrong: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let accentOn: Color
    let danger: Color

    // MARK: 0.4.0 — 켜진 것의 색 · 표면 위계

    /// 켜진 것의 **테두리·점·배지** 색 — 잉크(다크는 오프화이트). 이름이 brand인 이유는 머리말에.
    let brand: Color
    /// 켜진 것의 **글자·아이콘** 색 — 잉크.
    let brandInk: Color
    /// 켜진 칩·내 반응의 배경. 채움이 아니라 옅은 면(sunken) — 검정 채움 칩이 사라지는 자리다.
    let brandSoft: Color
    /// 카드처럼 **떠 있는** 표면. 라이트는 surface와 같고 그림자로 뜨고, 다크는 한 단 밝다 —
    /// 다크에서 카드가 배경에 붙던 것(감사 G8)을 면 값으로 가른다.
    let surfaceRaised: Color
    /// 시트·모달 뒤 스크림, 이미지 위 그라데이션의 시작색.
    let scrim: Color

    static let light = Palette(
        bg: Color(hex: 0xFAFAF8),
        surface: Color(hex: 0xFFFFFF),
        surfaceSunken: Color(hex: 0xF2F2EE),
        border: Color(hex: 0xE6E6E2),
        borderStrong: Color(hex: 0xC9C9C4),
        textPrimary: Color(hex: 0x0A0A0B),
        textSecondary: Color(hex: 0x9A9A95),
        accent: Color(hex: 0x0A0A0B),
        accentOn: Color(hex: 0xFFFFFF),
        danger: Color(hex: 0xFF3B30),
        brand: Color(hex: 0x0A0A0B),
        brandInk: Color(hex: 0x0A0A0B),
        brandSoft: Color(hex: 0xF2F2EE),
        surfaceRaised: Color(hex: 0xFFFFFF),
        scrim: Color(hex: 0x0A0A0B, alpha: 0.45)
    )

    static let dark = Palette(
        bg: Color(hex: 0x0A0A0B),
        surface: Color(hex: 0x161618),
        surfaceSunken: Color(hex: 0x1E1E21),
        border: Color(hex: 0x232327),
        borderStrong: Color(hex: 0x3A3A3E),
        textPrimary: Color(hex: 0xF5F5F4),
        textSecondary: Color(hex: 0x7A7A7E),
        accent: Color(hex: 0xF5F5F4),
        accentOn: Color(hex: 0x0A0A0B),
        danger: Color(hex: 0xFF453A),
        brand: Color(hex: 0xF5F5F4),
        brandInk: Color(hex: 0xF5F5F4),
        brandSoft: Color(hex: 0x1E1E21),
        surfaceRaised: Color(hex: 0x1B1B1E),
        scrim: Color(hex: 0x000000, alpha: 0.6)
    )

    static func of(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Spacing / radius / layout / duration

/// 4px 기본 그리드. 원본의 숫자 키(`spacing[4]`)를 이름으로 옮겼다.
enum Spacing {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    /// 기본 화면 gutter
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
}

enum Radius {
    /// 인풋, 버튼
    static let sm: CGFloat = 10
    /// 카드, 포스트
    static let md: CGFloat = 14
    /// 시트, 큰 미디어
    static let lg: CGFloat = 20
}

enum Layout {
    /// 최소 히트 타깃
    static let tapTarget: CGFloat = 44
}

enum Duration {
    static let fast: TimeInterval = 0.12
    /// 이미지 페이드인처럼 "도착했다"를 알리는 전환
    static let medium: TimeInterval = 0.22
}

/* 움직임 — 셋뿐이다. 화면마다 곡선을 새로 고르면 앱이 여러 사람이 만든 것처럼 움직인다.
 *   quick     칩·토글처럼 손끝에서 즉시 반응하는 것
 *   standard  카드 등장·리스트 삽입처럼 화면 안에서 자리를 잡는 것
 *   emphasized 시트·커버처럼 화면이 통째로 바뀌는 것 */
enum Motion {
    static let quick: Animation = .easeOut(duration: Duration.fast)
    static let standard: Animation = .spring(response: 0.34, dampingFraction: 0.86)
    static let emphasized: Animation = .spring(response: 0.48, dampingFraction: 0.82)
}

// MARK: - 떠 있는 표면

/* 카드가 배경에서 뜨게 한다. 라이트는 **그림자**(면 색이 배경과 거의 같아 그림자만이 경계다),
 * 다크는 그림자가 안 보이므로 **한 단 밝은 면 + 헤어라인**으로 뜬다. 흰 프레임 포스트가 배경과
 * 붙던 것(감사·피드)을 이 하나로 가른다 — 카드마다 그림자 값을 고르지 않는다. */
struct RaisedSurface: ViewModifier {
    var cornerRadius: CGFloat = Radius.lg

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let isDark = scheme == .dark
        content
            .background(palette.surfaceRaised, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                if isDark {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(palette.borderStrong.opacity(0.6), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(isDark ? 0 : 0.07), radius: 16, y: 6)
            .shadow(color: .black.opacity(isDark ? 0 : 0.04), radius: 2, y: 1)
    }
}

extension View {
    func raised(cornerRadius: CGFloat = Radius.lg) -> some View {
        modifier(RaisedSurface(cornerRadius: cornerRadius))
    }
}

// MARK: - Hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Environment access

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

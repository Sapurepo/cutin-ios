/* CUTIN 디자인 토큰 — cutin-frontend `packages/tokens`에서 1:1 이식.
 * 모노크롬(잉크/오프화이트) tone-on-tone. 위계는 FILL/OUTLINE/WEIGHT/SIZE로 만들고 hue로 만들지 않는다.
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
    let scrim: Color
    let overlay: Color

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
        scrim: Color(hex: 0x0A0A0B, alpha: 0.55),
        overlay: Color(hex: 0x0A0A0B, alpha: 0.04)
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
        scrim: Color(hex: 0x000000, alpha: 0.6),
        overlay: Color(hex: 0xF5F5F4, alpha: 0.06)
    )

    static func of(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Spacing / radius / layout / duration

/// 4px 기본 그리드. 원본의 숫자 키(`spacing[4]`)를 이름으로 옮겼다.
enum Spacing {
    static let x0: CGFloat = 0
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    /// 기본 화면 gutter
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
    static let x10: CGFloat = 40
    static let x12: CGFloat = 48
}

enum Radius {
    /// 칩, 작은 컨트롤
    static let xs: CGFloat = 6
    /// 인풋, 버튼
    static let sm: CGFloat = 10
    /// 카드, 포스트
    static let md: CGFloat = 14
    /// 시트, 큰 미디어
    static let lg: CGFloat = 20
    /// 캡슐 칩, 아바타, 촬영 FAB
    static let pill: CGFloat = 999
}

enum Layout {
    /// 모바일 캔버스 상한
    static let appMaxWidth: CGFloat = 430
    /// 하단 탭바
    static let navHeight: CGFloat = 64
    /// 상단 앱바
    static let headerHeight: CGFloat = 52
    /// 최소 히트 타깃
    static let tapTarget: CGFloat = 44
}

enum Duration {
    static let fast: TimeInterval = 0.12
    static let base: TimeInterval = 0.2
    static let slow: TimeInterval = 0.32
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

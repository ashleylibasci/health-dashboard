import SwiftUI

/// Colors from the canvas designs. Each metric keeps its hue in both modes:
/// dark mode uses the bright tones from the Watch, light mode uses darker
/// shades that pass 4.5:1 on white.
enum Accent: CaseIterable {
    case indigo, purple, coral, pink, mint, yellow, blue, orange

    /// Text, thin strokes and icons.
    func ink(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.indigo, .dark): Color(hex: 0xAEB8FF)
        case (.purple, .dark): Color(hex: 0xC7B8FF)
        case (.coral, .dark): Color(hex: 0xFF9A7A)
        case (.pink, .dark): Color(hex: 0xFF6B8A)
        case (.mint, .dark): Color(hex: 0x5EE0C1)
        case (.yellow, .dark): Color(hex: 0xFFD666)
        case (.blue, .dark): Color(hex: 0x6FB8FF)
        case (.orange, .dark): Color(hex: 0xFFB866)
        case (.indigo, _): Color(hex: 0x3E4CC9)
        case (.purple, _): Color(hex: 0x6A4FD6)
        case (.coral, _): Color(hex: 0xA84B24)
        case (.pink, _): Color(hex: 0xC2335A)
        case (.mint, _): Color(hex: 0x1E7A52)
        case (.yellow, _): Color(hex: 0x8A6200)
        case (.blue, _): Color(hex: 0x1F6FC4)
        case (.orange, _): Color(hex: 0xA85A00)
        }
    }

    /// Rings, bars and chart marks.
    func fill(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.indigo, .dark): Color(hex: 0x7C8BFF)
        case (.purple, .dark): Color(hex: 0x9B86FF)
        case (.coral, .dark): Color(hex: 0xFF9A7A)
        case (.pink, .dark): Color(hex: 0xFF6B8A)
        case (.mint, .dark): Color(hex: 0x5EE0C1)
        case (.yellow, .dark): Color(hex: 0xFFD666)
        case (.blue, .dark): Color(hex: 0x6FB8FF)
        case (.orange, .dark): Color(hex: 0xFFA94D)
        case (.indigo, _): Color(hex: 0x5B6BE8)
        case (.purple, _): Color(hex: 0x9B86FF)
        case (.coral, _): Color(hex: 0xF08A68)
        case (.pink, _): Color(hex: 0xFF6B8A)
        case (.mint, _): Color(hex: 0x2FA472)
        case (.yellow, _): Color(hex: 0xE0A800)
        case (.blue, _): Color(hex: 0x4A9BEA)
        case (.orange, _): Color(hex: 0xF28C28)
        }
    }

    /// Tinted card backgrounds.
    func tint(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? fill(.dark).opacity(0.14) : fill(.light).opacity(0.12)
    }
}

/// Neutral tokens.
struct Palette {
    let scheme: ColorScheme
    var background: Color { scheme == .dark ? .black : Color(hex: 0xF6F6FA) }
    var card: Color { scheme == .dark ? Color.white.opacity(0.07) : .white }
    var cardBorder: Color { scheme == .dark ? Color.white.opacity(0.09) : Color(hex: 0xE6E6EF) }
    var primary: Color { scheme == .dark ? .white : Color(hex: 0x1C1E33) }
    var secondary: Color { scheme == .dark ? Color.white.opacity(0.68) : Color(hex: 0x4A4F6E) }
    var tertiary: Color { scheme == .dark ? Color.white.opacity(0.6) : Color(hex: 0x6B6F8A) }
    var track: Color { scheme == .dark ? Color.white.opacity(0.12) : Color(hex: 0xECECF3) }
    var chip: Color { scheme == .dark ? Color.white.opacity(0.08) : Color(hex: 0xF1F1F6) }
    /// The soft glow at the top of every screen.
    func glow(_ accent: Accent) -> RadialGradient {
        RadialGradient(colors: [accent.fill(scheme).opacity(scheme == .dark ? 0.55 : 0.16), .clear],
                       center: .top, startRadius: 0, endRadius: 420)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// Rounded system font for big numbers, as in the designs.
extension Font {
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

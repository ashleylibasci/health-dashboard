import SwiftUI

/// Colors from the canvas designs. Each metric keeps its hue in both modes:
/// dark mode uses the bright tones from the Watch, light mode uses darker
/// shades. Light inks pass 4.5:1 on white and on their own tint; light
/// fills pass 3:1 on white, so a thin chart line or ring arc stays visible.
/// Purple sits at hue 304° (OKLCH) so it no longer reads as a second indigo.
enum Accent: CaseIterable {
    case indigo, purple, coral, pink, mint, yellow, blue, orange

    /// Text, thin strokes and icons.
    func ink(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.indigo, .dark): Color(hex: 0xAEB8FF)
        case (.purple, .dark): Color(hex: 0xD6B8FF)
        case (.coral, .dark): Color(hex: 0xFF9A7A)
        case (.pink, .dark): Color(hex: 0xFF6B8A)
        case (.mint, .dark): Color(hex: 0x5EE0C1)
        case (.yellow, .dark): Color(hex: 0xFFD666)
        case (.blue, .dark): Color(hex: 0x6FB8FF)
        case (.orange, .dark): Color(hex: 0xFFB866)
        case (.indigo, _): Color(hex: 0x3E4CC9)
        case (.purple, _): Color(hex: 0x7440C0)
        case (.coral, _): Color(hex: 0xA84B24)
        case (.pink, _): Color(hex: 0xC2335A)
        case (.mint, _): Color(hex: 0x1E7A52)
        case (.yellow, _): Color(hex: 0x7A5600)
        case (.blue, _): Color(hex: 0x1A5CA8)
        case (.orange, _): Color(hex: 0xA85A00)
        }
    }

    /// Rings, bars and chart marks.
    func fill(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.indigo, .dark): Color(hex: 0x7C8BFF)
        case (.purple, .dark): Color(hex: 0xC08BFF)
        case (.coral, .dark): Color(hex: 0xFF9A7A)
        case (.pink, .dark): Color(hex: 0xFF6B8A)
        case (.mint, .dark): Color(hex: 0x5EE0C1)
        case (.yellow, .dark): Color(hex: 0xFFD666)
        case (.blue, .dark): Color(hex: 0x6FB8FF)
        case (.orange, .dark): Color(hex: 0xFFA94D)
        case (.indigo, _): Color(hex: 0x5B6BE8)
        case (.purple, _): Color(hex: 0x8A4FD6)
        case (.coral, _): Color(hex: 0xD9653F)
        case (.pink, _): Color(hex: 0xE0446A)
        case (.mint, _): Color(hex: 0x23935F)
        case (.yellow, _): Color(hex: 0xB88A00)
        case (.blue, _): Color(hex: 0x2F86DB)
        case (.orange, _): Color(hex: 0xD2700A)
        }
    }

    /// Tinted card backgrounds.
    func tint(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? fill(.dark).opacity(0.14) : fill(.light).opacity(0.12)
    }

    /// Text and icons on a chip or button that sits on this accent's tinted
    /// card (a fill at ~0.2 over the tint), where the plain light ink drops
    /// under 4.5:1. Dark mode uses the ink.
    func onTint(_ scheme: ColorScheme) -> Color {
        guard scheme != .dark else { return ink(.dark) }
        switch self {
        case .indigo: return Color(hex: 0x3C49C1)
        case .purple: return Color(hex: 0x553BBD)
        case .coral: return Color(hex: 0x90401F)
        case .pink: return Color(hex: 0x9B2948)
        case .mint: return Color(hex: 0x196443)
        case .yellow: return Color(hex: 0x7A5600)
        case .blue: return Color(hex: 0x1A5CA8)
        case .orange: return Color(hex: 0x8A4A00)
        }
    }

    /// The faint full circle behind a ring's arc, visible in both modes.
    func track(_ scheme: ColorScheme) -> Color {
        fill(scheme).opacity(scheme == .dark ? 0.2 : 0.28)
    }
}

/// Stress level fills (Low, Usual, Raised, High). Lightness steps with the
/// level so "High" never differs from "Raised" by hue alone: in light mode
/// High is a deep red (6.5:1 on white) next to an amber Raised (3.5:1), and
/// every fill is at least 3:1 on white; in dark mode Raised is a pale amber
/// and High a strong red, both 5:1 or more on the dark card.
enum StressLevelColor {
    /// `level`: 0 Low, 1 Usual, 2 Raised, 3 High.
    static func fill(_ level: Int, _ scheme: ColorScheme) -> Color {
        switch (min(max(level, 0), 3), scheme) {
        case (0, .dark): Color(hex: 0x5EE0C1)
        case (1, .dark): Color(hex: 0x6FB8FF)
        case (2, .dark): Color(hex: 0xFFC266)
        case (_, .dark): Color(hex: 0xFF5A5A)
        case (0, _): Color(hex: 0x2FA472)
        case (1, _): Color(hex: 0x2F7FD6)
        case (2, _): Color(hex: 0xC77700)
        default: Color(hex: 0xB3261E)
        }
    }
}

/// Neutral tokens.
struct Palette {
    let scheme: ColorScheme
    var background: Color { scheme == .dark ? .black : Color(hex: 0xF6F6FA) }
    var card: Color { scheme == .dark ? Color.white.opacity(0.07) : .white }
    var cardBorder: Color { scheme == .dark ? Color.white.opacity(0.09) : Color(hex: 0xE6E6EF) }
    var primary: Color { scheme == .dark ? .white : Color(hex: 0x1C1E33) }
    var secondary: Color { scheme == .dark ? Color.white.opacity(0.72) : Color(hex: 0x4A4F6E) }
    /// Still 5:1 on the dark card, but clearly a step below secondary.
    var tertiary: Color { scheme == .dark ? Color.white.opacity(0.52) : Color(hex: 0x6B6F8A) }
    var track: Color { scheme == .dark ? Color.white.opacity(0.12) : Color(hex: 0xDFDFEA) }
    var chip: Color { scheme == .dark ? Color.white.opacity(0.08) : Color(hex: 0xF1F1F6) }
    /// The soft glow at the top of every screen.
    func glow(_ accent: Accent) -> RadialGradient {
        RadialGradient(colors: [accent.fill(scheme).opacity(scheme == .dark ? 0.28 : 0.16), .clear],
                       center: .top, startRadius: 0, endRadius: 360)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// Rounded system font for big numbers, as in the designs. Tabular figures,
/// so a number that changes (a scrubbed readout, a running total) doesn't
/// jitter sideways.
extension Font {
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded).monospacedDigit() }
}

/// Spacing scale. Every gap, padding and gutter is one of these.
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    /// Stack spacing between cards on a screen, and grid gutters.
    static let m: CGFloat = 12
    /// Card padding.
    static let l: CGFloat = 16
    /// Screen side margins.
    static let xl: CGFloat = 20
    /// Above a section label (8 below it).
    static let section: CGFloat = 32
    /// Below the last card on a scrolling screen.
    static let scrollEnd: CGFloat = 32
}

/// Corner radii. Pills and chips that are fully round use `Capsule()`.
enum Radius {
    /// Cards, tiles and other surfaces.
    static let surface: CGFloat = 24
    /// Things inside a card: icon tiles, chips, callouts, inner boxes.
    static let inner: CGFloat = 12
    /// Chart bars and small marks.
    static let mark: CGFloat = 4
}

/// Fixed sizes for touch targets and icons.
enum Sizes {
    /// Smallest tap target.
    static let minTap: CGFloat = 44
    /// A row that holds two lines (title and subtitle) or a primary button.
    static let tallRow: CGFloat = 56
    /// The rounded-square icon tile at the start of a row.
    static let icon: CGFloat = 36
}

import SwiftUI
import UIKit

/// Fonts that follow the iPhone's text size (Settings › Display & Brightness ›
/// Text Size, and Accessibility › Larger Text).
///
/// The designs use exact point sizes, so every screen asks for
/// `.scaled(size:)` with the design size, and this scales it like body text.
/// Very large accessibility sizes are capped at 2.2× so layouts stay usable.
/// Changing the text size takes the app through inactive → active, and the
/// refresh that follows re-renders the screens with the new sizes. No forced
/// rebuild, so open screens and onboarding progress survive.
extension Font {
    static func scaled(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: scaledSize(size), weight: weight, design: design)
    }

    /// The rounded bold numerals used for big numbers, scaled. Tabular
    /// figures, so changing numbers don't jitter sideways.
    static func scaledNumber(_ size: CGFloat) -> Font {
        .system(size: scaledSize(size), weight: .bold, design: .rounded).monospacedDigit()
    }

    static func scaledSize(_ size: CGFloat) -> CGFloat {
        min(UIFontMetrics(forTextStyle: .body).scaledValue(for: size), size * 2.2)
    }
}


/// The type scale. Every piece of text in the shared components uses one of
/// these roles; screens should too, instead of a literal size.
///
/// | Role | Size | Weight | Tracking | Scaling cap |
/// |---|---|---|---|---|
/// | displayXL | 56 | Bold rounded, tabular | 0 | 1.6× |
/// | display | 40 | Bold rounded, tabular | 0 | 1.6× |
/// | numberL | 28 | Bold rounded, tabular | 0 | 1.6× |
/// | numberM | 22 | Bold rounded, tabular | 0 | 1.6× |
/// | screenTitle (Large Title) | 34 | Bold | −0.4 | 1.6× |
/// | detailTitle (Title) | 28 | Bold | −0.3 | 1.6× |
/// | heading (Headline) | 22 | Bold | −0.2 | 1.6× |
/// | section | 20 | Bold | 0 | 2.2× |
/// | cardTitle | 17 | Semibold | 0 | 2.2× |
/// | bodyText | 15 | Regular | 0 | 2.2× |
/// | bodyEmphasis | 15 | Semibold | 0 | 2.2× |
/// | secondary | 13 | Regular | 0 | 2.2× |
/// | caps | 12 | Semibold, uppercased by `CapsLabel` | +0.6 | 2.2× |
/// | small (Caption) | 11 | Regular | 0 | 2.2× |
///
/// Use it with `.font(.cardTitle)`, which also applies the tracking, or
/// `Font.role(.cardTitle)` where a `Font` is needed (`Text` concatenation).
/// No case shares a name with SwiftUI's `Font` (`.body`, `.title`, …), so
/// `.font(.body)` still means the system text style.
enum TypeRole: CaseIterable {
    case displayXL, display, numberL, numberM
    case screenTitle, detailTitle, heading, section, cardTitle
    case bodyText, bodyEmphasis, secondary, caps, small

    /// The design size at the default text size.
    var size: CGFloat {
        switch self {
        case .displayXL: 56
        case .display: 40
        case .numberL: 28
        case .numberM: 22
        case .screenTitle: 34
        case .detailTitle: 28
        case .heading: 22
        case .section: 20
        case .cardTitle: 17
        case .bodyText, .bodyEmphasis: 15
        case .secondary: 13
        case .caps: 12
        case .small: 11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .displayXL, .display, .numberL, .numberM, .screenTitle, .detailTitle, .heading, .section: .bold
        case .cardTitle, .bodyEmphasis, .caps: .semibold
        case .bodyText, .secondary, .small: .regular
        }
    }

    var tracking: CGFloat {
        switch self {
        case .screenTitle: -0.4
        case .detailTitle: -0.3
        case .heading: -0.2
        case .caps: 0.6
        default: 0
        }
    }

    /// Big numerals: rounded, with tabular figures.
    var isNumber: Bool {
        switch self {
        case .displayXL, .display, .numberL, .numberM: true
        default: false
        }
    }

    /// Display, title and number roles stop growing at 1.6×, like
    /// `headingScaled`, so a hero never outgrows the text around it.
    var isCapped: Bool {
        switch self {
        case .displayXL, .display, .numberL, .numberM, .screenTitle, .detailTitle, .heading: true
        default: false
        }
    }

    /// The scaled point size for the current text size.
    var scaledSize: CGFloat {
        isCapped ? min(Font.scaledSize(size), size * 1.6) : Font.scaledSize(size)
    }

    var font: Font {
        let base = Font.system(size: scaledSize, weight: weight, design: isNumber ? .rounded : .default)
        return isNumber ? base.monospacedDigit() : base
    }
}

extension Font {
    /// The font for a role in the type scale, without its tracking.
    static func role(_ role: TypeRole) -> Font { role.font }
}

extension View {
    /// Applies a role from the type scale: font and tracking.
    func font(_ role: TypeRole) -> some View {
        font(role.font).tracking(role.tracking)
    }
}

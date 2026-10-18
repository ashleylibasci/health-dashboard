import SwiftUI

/// The Morning light palette from the "Health Dashboard Layouts" canvas, with a warm dark
/// "night" version (after 8pm) built from the canvas's dark Watch screen.
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// A color that switches with light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
        #else
        // The Watch draws its own day and night looks, so it always uses the light values.
        self.init(hex: light)
        #endif
    }

    static let ground = Color(light: 0xFAFAF7, dark: 0x111325)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1F36)
    static let ink = Color(light: 0x1D2142, dark: 0xF1F2FA)
    static let muted = Color(light: 0x5A5F7A, dark: 0xB4B7CF)
    /// Secondary text on tinted cards.
    static let muted2 = Color(light: 0x4A4F6E, dark: 0xC8CBE0)
    static let main = Color(hex: 0x7C8CF8)
    static let mainText = Color(light: 0x4453C9, dark: 0xA3AEFF)
    static let line = Color(light: 0xECECF2, dark: 0x2C3050)
    static let track = Color(light: 0xF3F3F7, dark: 0x2A2D48)
    static let lavender = Color(light: 0xECEEFF, dark: 0x252A52)
    static let periwinkle = Color(light: 0xE4E7FF, dark: 0x2B3160)
    static let lavenderStrong = Color(light: 0xC9CFFF, dark: 0x3B4384)
    static let peach = Color(light: 0xFFE8DE, dark: 0x3D2721)
    static let peachInk = Color(light: 0xB04A2E, dark: 0xFFB59A)
    static let peachBar = Color(hex: 0xFFB59A)
    static let blush = Color(light: 0xFFF1EA, dark: 0x382A25)
    static let rose = Color(light: 0xFFE6E2, dark: 0x3F2629)
    static let butter = Color(light: 0xFFF4CC, dark: 0x3A3220)
    static let butterInk = Color(light: 0x7A5A00, dark: 0xFFD966)
    static let mint = Color(light: 0xDDF5EA, dark: 0x1B3B2F)
    static let mintInk = Color(light: 0x1F7A55, dark: 0x7FD9AE)
    static let lilac = Color(light: 0xF3E9FF, dark: 0x30264A)
    static let lilacInk = Color(light: 0x7A3FC2, dark: 0xCFA9FF)
    /// The dark pill buttons, which turn light at night.
    static let solid = Color(light: 0x1D2142, dark: 0xE6E8FF)
    static let onSolid = Color(light: 0xFFFFFF, dark: 0x15172B)
}

/// The design pairs Fraunces (headlines), Bricolage Grotesque (numbers) and Instrument Sans (text).
/// Until those font files are bundled, Apple's serif and rounded system faces stand in.
extension Font {
    static func serifTitle(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let label = Font.system(size: 13, weight: .bold)
}

/// The design's point sizes, scaled with the person's text-size setting (Dynamic Type).
/// At the default size the text is exactly the canvas size; it grows like the closest text style.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let base: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(_ size: CGFloat, weight: Font.Weight, design: Font.Design) {
        base = size
        self.weight = weight
        self.design = design
        _size = ScaledMetric(wrappedValue: size, relativeTo: ScaledFont.style(for: size))
    }

    /// Big display numbers and headlines grow less than body text so they still fit a row.
    private static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 30...: .largeTitle
        case 26..<30: .title
        case 21..<26: .title2
        case 19..<21: .title3
        case 17..<19: .body
        case 16..<17: .callout
        case 14..<16: .subheadline
        case 13..<14: .footnote
        case 12..<13: .caption
        default: .caption2
        }
    }

    func body(content: Content) -> some View {
        let capped = base >= 30 ? min(size, base * 2) : size
        content.font(.system(size: capped, weight: weight, design: design))
    }
}

extension View {
    /// `.font(.system(size:weight:design:))` that follows Dynamic Type.
    func scaledFont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size, weight: weight, design: design))
    }
    /// `.font(.serifTitle(size))` that follows Dynamic Type.
    func serifTitleFont(_ size: CGFloat) -> some View { scaledFont(size, .medium, design: .serif) }
    /// `.font(.number(size))` that follows Dynamic Type.
    func numberFont(_ size: CGFloat) -> some View { scaledFont(size, .bold, design: .rounded) }
    /// `.font(.label)` that follows Dynamic Type.
    func labelFont() -> some View { scaledFont(13, .bold) }
}

extension View {
    /// For icons in fixed-size boxes and other decoration: grows a little with the text size, then stops.
    func limitedTextGrowth() -> some View { dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
}

/// A row that stacks its parts, leading-aligned, at the accessibility text sizes,
/// where side by side no longer fits. Stacked, it takes its natural height, so a row's
/// `Spacer` shrinks to its minimum instead of opening a gap, and the full width, like the row did.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) { content }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: alignment, spacing: spacing) { content }
        }
    }
}

/// A grid of equal columns that drops to `accessibilityColumns` (one, unless set) at the
/// accessibility text sizes.
struct AdaptiveGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var columns: Int
    var accessibilityColumns = 1
    var spacing: CGFloat
    var rowSpacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        let count = typeSize.isAccessibilitySize ? min(columns, accessibilityColumns) : columns
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: count), spacing: rowSpacing ?? spacing) { content }
    }
}

/// A rounded card; `fill` is the card's tint.
struct Card<Content: View>: View {
    var fill: Color = .surface
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(fill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: fill == .surface ? Color(red: 20 / 255, green: 20 / 255, blue: 40 / 255).opacity(0.06) : .clear, radius: 1, y: 1)
    }
}

/// The small uppercase heading at the top of a card.
struct CardLabel: View {
    var text: String
    var color: Color = .mainText
    init(_ text: String, color: Color = .mainText) { self.text = text; self.color = color }

    var body: some View {
        Text(text.uppercased()).labelFont().kerning(0.8).foregroundStyle(color)
    }
}

/// A tinted stat tile: label, big number, optional caption.
struct Tile: View {
    var label: String
    var value: String
    var caption: String?
    var fill: Color
    var ink: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).scaledFont(11, .bold).foregroundStyle(ink).lineLimit(2).minimumScaleFactor(0.8)
            Text(value).numberFont(20).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.7)
            if let caption { Text(caption).scaledFont(13).foregroundStyle(Color.muted).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct Pill: View {
    var text: String
    var fill: Color
    var ink: Color

    var body: some View {
        Text(text).scaledFont(13, .bold).foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(fill, in: Capsule())
    }
}

/// Muted explanatory text under a card's numbers.
struct Note: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).scaledFont(14).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
    }
}

/// "+4 bpm", "−7 ms", or "no data".
func signed(_ v: Double?, _ unit: String) -> String {
    guard let v else { return "no data" }
    let r = Int(v.rounded())
    return "\(r > 0 ? "+" : r < 0 ? "−" : "")\(abs(r))\(unit)"
}

extension View {
    /// The shared page frame: Morning light ground, scrolling, comfortable side margins.
    func page() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { self }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .background(Color.ground)
    }
}

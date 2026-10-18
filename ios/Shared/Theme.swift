import SwiftUI

/// The Morning light palette from the "Health Dashboard Layouts" canvas.
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static let ground = Color(hex: 0xFAFAF7)
    static let surface = Color.white
    static let ink = Color(hex: 0x1D2142)
    static let muted = Color(hex: 0x5A5F7A)
    static let main = Color(hex: 0x7C8CF8)
    static let mainText = Color(hex: 0x4453C9)
    static let line = Color(hex: 0xECECF2)
    static let track = Color(hex: 0xF3F3F7)
    static let lavender = Color(hex: 0xECEEFF)
    static let peach = Color(hex: 0xFFE8DE)
    static let peachInk = Color(hex: 0xB04A2E)
    static let peachBar = Color(hex: 0xFFB59A)
    static let butter = Color(hex: 0xFFF4CC)
    static let butterInk = Color(hex: 0x7A5A00)
    static let mint = Color(hex: 0xDDF5EA)
    static let mintInk = Color(hex: 0x1F7A55)
}

/// The design pairs Fraunces (headlines), Bricolage Grotesque (numbers) and Instrument Sans (text).
/// Until those font files are bundled, Apple's serif and rounded system faces stand in.
extension Font {
    static func serifTitle(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let label = Font.system(size: 13, weight: .bold)
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
        Text(text.uppercased()).font(.label).kerning(0.8).foregroundStyle(color)
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
            Text(label.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(ink).lineLimit(1)
            Text(value).font(.number(20)).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.7)
            if let caption { Text(caption).font(.system(size: 13)).foregroundStyle(Color.muted).lineLimit(1) }
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
        Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(fill, in: Capsule())
    }
}

/// Muted explanatory text under a card's numbers.
struct Note: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
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

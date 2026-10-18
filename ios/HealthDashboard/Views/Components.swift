import SwiftUI

/// The recovery ring from the canvas.
struct Ring: View {
    var value: Int?
    var size: CGFloat = 96
    var track: Color = .surface
    /// The ring grows with the text size so the number inside stays readable.
    @ScaledMetric(relativeTo: .title) private var scale = 1.0

    var body: some View {
        let size = size * min(scale, 1.6)
        ZStack {
            Circle().stroke(track, lineWidth: size * 0.115)
            Circle().trim(from: 0, to: CGFloat(value ?? 0) / 100)
                .stroke(Color.main, style: StrokeStyle(lineWidth: size * 0.115, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(value.map(String.init) ?? "–").numberFont(self.size * 0.3).foregroundStyle(Color.ink)
                .lineLimit(1).minimumScaleFactor(0.5).padding(size * 0.16)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(value.map { "Recovery \($0) out of 100" } ?? "Recovery not ready yet")
    }
}

/// Simple vertical bars, values 0–1, with an optional color per bar.
struct Bars: View {
    var values: [Double]
    var colors: [Color]? = nil
    var height: CGFloat = 80
    var spacing: CGFloat = 5

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(values.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(colors?[i] ?? Color(hex: 0xC9CFFF))
                    .frame(height: max(4, height * CGFloat(min(1, max(0, values[i])))))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// A horizontal progress bar.
struct Meter: View {
    var value: Double
    var color: Color = .main
    var track: Color = .track
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A card-shaped navigation link with an icon, title and one-line detail.
struct LinkCard: View {
    var icon: String
    var title: String
    var detail: String
    var fill: Color = .surface
    var iconFill: Color = .lavender
    var iconInk: Color = .mainText
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            // At the accessibility sizes the icon sits above the words so they get the full width.
            AdaptiveStack(spacing: 12) {
                Image(systemName: icon).scaledFont(18).foregroundStyle(iconInk).limitedTextGrowth()
                    .frame(width: 40, height: 40).background(iconFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).scaledFont(15, .bold).foregroundStyle(Color.ink)
                    Text(detail).scaledFont(13).foregroundStyle(Color.muted).lineLimit(typeSize.isAccessibilitySize ? nil : 2).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").scaledFont(13, .bold).foregroundStyle(Color.muted).limitedTextGrowth()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: fill == .surface ? Color(red: 20 / 255, green: 20 / 255, blue: 40 / 255).opacity(0.06) : .clear, radius: 1, y: 1)
    }
}

/// A rounded chip button, filled when selected.
struct Chip: View {
    var text: String
    var selected = false
    var fill: Color = .surface
    var selectedFill: Color = .lavenderStrong
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text).scaledFont(14, selected ? .bold : .semibold).foregroundStyle(Color.ink)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(selected ? selectedFill : fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A bulleted line inside a card.
struct Bullet: View {
    var text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("·").fontWeight(.bold)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .scaledFont(15).foregroundStyle(Color.ink)
    }
}

/// A label + value row.
struct ValueRow: View {
    var label: String
    var value: String
    var valueColor: Color = .ink
    var body: some View {
        AdaptiveStack(spacing: 2) {
            Text(label).foregroundStyle(Color.ink)
            Spacer(minLength: 8)
            Text(value).fontWeight(.bold).foregroundStyle(valueColor)
        }
        .scaledFont(15)
    }
}

/// A big serif page title with an italic accent, as in the canvas.
struct PageTitle: View {
    var plain: String
    var accent: String = ""
    var after: String = ""
    var body: some View {
        (Text(plain) + Text(accent).italic().foregroundColor(.mainText) + Text(after))
            .serifTitleFont(34).foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A full-width dark pill button.
struct PrimaryButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).scaledFont(16, .bold)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Color.onSolid).background(Color.solid, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// A pushed detail screen: the shared page frame with a plain back button.
    func detailPage() -> some View {
        page()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ground, for: .navigationBar)
    }
}

/// Phase colors from the canvas.
extension CyclePhase {
    var color: Color {
        switch self {
        case .period: Color(hex: 0xF07A6B)
        case .follicular: Color(hex: 0xFFD2BD)
        case .ovulation: Color(hex: 0x5B6BE8)
        case .luteal: Color(hex: 0xC9CFFF)
        }
    }
    var tint: Color {
        switch self {
        case .period: Color.rose
        case .follicular: Color.blush
        case .ovulation: Color.periwinkle
        case .luteal: Color.lavender
        }
    }
}

/// Grouped caffeine buttons: espresso shots, energy drinks, coffee and tea.
struct CaffeinePicker: View {
    var log: (CaffeineDrink) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(caffeineGroups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title).scaledFont(13, .bold).foregroundStyle(Color.butterInk)
                    FlowLayout {
                        ForEach(group.drinks, id: \.self) { d in
                            Chip(text: "\(d.name) · \(Int(d.mg))", fill: .butter) { log(d) }
                                .accessibilityLabel("Log \(d.name), \(Int(d.mg)) milligrams")
                        }
                    }
                }
            }
        }
    }
}

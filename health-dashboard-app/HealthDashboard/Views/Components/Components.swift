import SwiftUI
import HealthCore

// Shared building blocks so every screen matches the designs.

/// A scrolling screen with the accent glow at the top.
struct Screen<Content: View>: View {
    var title: String? = nil
    var accent: Accent = .indigo
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                p.background
                p.glow(accent).frame(height: 460)
            }
            .ignoresSafeArea()
        }
        .foregroundStyle(p.primary)
        .navigationTitle(title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The standard rounded card. Pass an accent for a tinted card.
struct Card<Content: View>: View {
    var accent: Accent? = nil
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.map { $0.tint(scheme) } ?? p.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(accent.map { $0.fill(scheme).opacity(0.22) } ?? p.cardBorder))
            .shadow(color: scheme == .light && accent == nil ? Color(hex: 0x141428, alpha: 0.06) : .clear, radius: 1, y: 1)
    }
}

/// Small uppercase label above a section.
struct SectionLabel: View {
    var text: String
    var accent: Accent? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text.uppercased())
            .font(.scaled(size: 12, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(accent?.ink(scheme) ?? Palette(scheme: scheme).secondary)
    }
}

/// A progress ring with a big number in the middle.
struct Ring: View {
    var value: Double              // 0...1
    var accent: Accent
    var lineWidth: CGFloat = 14
    var label: String
    var caption: String? = nil
    var size: CGFloat = 118
    /// What VoiceOver reads. Defaults to "caption: label" ("Recovery: 82";
    /// a cycle caption "Day of ~29" reads "Day 22 of about 29").
    var accessibilityText: String? = nil
    @Environment(\.colorScheme) private var scheme

    private var spokenText: String {
        if let accessibilityText { return accessibilityText }
        guard let caption, !caption.isEmpty else { return label }
        if caption.hasPrefix("Day of ") {
            let rest = caption.dropFirst("Day of ".count).replacingOccurrences(of: "~", with: "about ")
            return "Day \(label) of \(rest)"
        }
        return "\(caption): \(label)"
    }

    var body: some View {
        ZStack {
            Circle().stroke(accent.fill(scheme).opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(value, 1)))
                .stroke(LinearGradient(colors: [accent.ink(scheme).opacity(scheme == .dark ? 1 : 0.7), accent.fill(scheme)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Number and caption shrink to fit inside the ring at large text sizes.
            VStack(spacing: 2) {
                Text(label)
                    .font(.scaledNumber(size * 0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                if let caption {
                    Text(caption.uppercased())
                        .font(.scaled(size: 11, weight: .bold))
                        .foregroundStyle(accent.ink(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
            }
            .padding(lineWidth)
            .padding(.horizontal, size * 0.04)
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }
}

/// A tile with a title, a big value and a note. Used in grids.
struct MetricTile: View {
    var title: String
    var value: String
    var note: String? = nil
    var accent: Accent
    var systemImage: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.scaled(size: 14, weight: .bold))
                Spacer()
                if let systemImage { Image(systemName: systemImage).foregroundStyle(accent.ink(scheme)).accessibilityHidden(true) }
            }
            Text(value).font(.scaledNumber(24)).minimumScaleFactor(0.6).lineLimit(1)
            if let note { Text(note).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(Palette(scheme: scheme).secondary) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// A row that navigates somewhere, with an icon tile and chevron.
struct LinkRow<Destination: View>: View {
    var title: String
    var subtitle: String? = nil
    var systemImage: String
    var accent: Accent
    @ViewBuilder var destination: Destination
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationLink { destination } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(accent.ink(scheme))
                    .frame(width: 36, height: 36)
                    .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.scaled(size: 15, weight: .bold))
                    if let subtitle { Text(subtitle).font(.scaled(size: 13)).foregroundStyle(Palette(scheme: scheme).secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.scaled(size: 13, weight: .bold)).foregroundStyle(Palette(scheme: scheme).tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A selectable chip; the selected one is filled with the accent.
struct Chip: View {
    var title: String
    var selected: Bool
    var accent: Accent = .indigo
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        Button(action: action) {
            Text(title)
                .font(.scaled(size: 14, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
                .foregroundStyle(selected ? selectedText : p.primary)
                .background(selected ? selectedFill : p.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? selectedFill : p.cardBorder))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // Light: white on the deep ink (5:1 or better for every accent).
    // Dark: near-black on the bright fill (6:1 or better).
    private var selectedFill: Color { scheme == .dark ? accent.fill(.dark) : accent.ink(.light) }
    private var selectedText: Color { scheme == .dark ? Color(hex: 0x1A0E00) : .white }
}

/// The big rounded primary button.
struct PrimaryButton: View {
    var title: String
    var accent: Accent = .indigo
    var done = false
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.scaled(size: 17, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(done ? Accent.mint.ink(scheme) : (scheme == .dark ? Color(hex: 0x0E1136) : .white))
                .background(done ? Accent.mint.tint(scheme) : (scheme == .dark ? accent.ink(.dark) : accent.ink(.light)),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A check / warning row used by "Why this time".
struct ReasonRow: View {
    var ok: Bool
    var title: String
    var detail: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark" : "exclamationmark")
                .font(.scaled(size: 11, weight: .heavy))
                .foregroundStyle((ok ? Accent.mint : Accent.coral).ink(scheme))
                .frame(width: 22, height: 22)
                .background((ok ? Accent.mint : Accent.coral).tint(scheme), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.scaled(size: 14, weight: .bold))
                Text(detail).font(.scaled(size: 13)).foregroundStyle(Palette(scheme: scheme).secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A horizontal bar showing a value against a track (used for "What moved today" etc.).
struct BarRow: View {
    var label: String
    var fraction: Double
    var valueText: String
    var accent: Accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // The fixed label and value columns were wider than the
                // screen at the largest sizes, which pushed whole screens
                // past their left gutter. Label and value above the bar.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(label).font(.scaled(size: 14, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(valueText).font(.scaled(size: 14, weight: .bold)).keepsOnOneLine()
                    }
                    bar
                }
            } else {
                HStack(spacing: 10) {
                    Text(label).font(.scaled(size: 14, weight: .semibold)).frame(width: Font.scaledSize(110), alignment: .leading)
                    bar
                    Text(valueText).font(.scaled(size: 14, weight: .bold)).frame(width: Font.scaledSize(52), alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette(scheme: scheme).track)
                Capsule().fill(accent.fill(scheme)).frame(width: geo.size.width * max(0, min(fraction, 1)))
            }
        }
        .frame(height: 10)
    }
}

extension View {
    /// Secondary text color for the current scheme.
    func secondaryText() -> some View { modifier(SecondaryText()) }
}

private struct SecondaryText: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.foregroundStyle(Palette(scheme: scheme).secondary) }
}

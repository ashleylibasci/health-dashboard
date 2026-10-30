import SwiftUI
import HealthCore

// Shared building blocks so every screen matches the designs. Sizes come
// from the tokens in Theme.swift (`Space`, `Radius`, `Sizes`), text from the
// type scale (`TypeRole`), movement from `Motion`.

/// A scrolling screen with the accent glow at the top.
struct Screen<Content: View>: View {
    var title: String? = nil
    var accent: Accent = .indigo
    /// Pull down to re-read Apple Health (off for onboarding).
    var refreshes = true
    /// Tab roots: the search field sits above the header, tucked away
    /// until she pulls down (D-S1).
    var searches = false
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let p = Palette(scheme: scheme)
        ScrollView {
            if searches {
                PullDownSearch {
                    VStack(alignment: .leading, spacing: Space.m) { content }
                }
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.scrollEnd)
            } else {
                VStack(alignment: .leading, spacing: Space.m) { content }
                    .padding(.horizontal, Space.xl)
                    .padding(.bottom, Space.scrollEnd)
            }
        }
        .modifier(SearchScrollBehavior(enabled: searches))
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                p.background
                p.glow(accent).frame(height: 460)
            }
            .ignoresSafeArea()
        }
        .foregroundStyle(p.primary)
        .modifier(PullToRefresh(enabled: refreshes) { await model.becameActive() })
        .navigationTitle(title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// `.refreshable` when `enabled`: the same refresh the app runs when it
/// comes to the front (Apple Health, then the Watch).
private struct PullToRefresh: ViewModifier {
    var enabled: Bool
    var action: () async -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}

/// How much room a card leaves around its content.
enum CardDensity {
    /// 16pt: the default for every card.
    case standard
    /// 12pt: cards that hold a list of rows (links, toggles), whose rows
    /// already have their own 44pt height.
    case compact

    var padding: CGFloat { self == .compact ? Space.m : Space.l }
}

/// The standard rounded card. Pass an accent for a tinted card.
struct Card<Content: View>: View {
    var accent: Accent? = nil
    var padding: CGFloat = Space.l
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
        VStack(alignment: .leading, spacing: Space.m) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.map { $0.tint(scheme) } ?? p.card, in: shape)
            // Tinted cards carry their colour without a border.
            .overlay(shape.strokeBorder(accent == nil ? p.cardBorder : .clear))
            .shadow(color: scheme == .light && accent == nil ? Color(hex: 0x141428, alpha: 0.06) : .clear, radius: 1, y: 1)
    }
}

extension Card {
    /// A card with the standard (16pt) or compact (12pt) padding.
    init(accent: Accent? = nil, density: CardDensity, @ViewBuilder content: () -> Content) {
        self.init(accent: accent, padding: density.padding, content: content)
    }
}

/// A small uppercase label: 12pt semibold, tracked +0.6. Section labels
/// and in-card eyebrows. VoiceOver reads it in sentence case, as a heading
/// unless `isHeader` is false.
struct CapsLabel: View {
    var text: String
    var color: Color? = nil
    var isHeader = true
    @Environment(\.colorScheme) private var scheme

    init(_ text: String, color: Color? = nil, isHeader: Bool = true) {
        self.text = text
        self.color = color
        self.isHeader = isHeader
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caps)
            .foregroundStyle(color ?? Palette(scheme: scheme).secondary)
            .accessibilityLabel(text)
            .accessibilityAddTraits(isHeader ? .isHeader : [])
    }
}

/// Small uppercase label above a section.
struct SectionLabel: View {
    var text: String
    var accent: Accent? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        CapsLabel(text, color: accent?.ink(scheme) ?? Palette(scheme: scheme).secondary)
    }
}

/// A progress ring with a big number in the middle.
///
/// `size` is the ring's outer edge: the stroke draws inside it, so the ring
/// never spills over its neighbours. It grows a little with the text size
/// (up to 1.3×). The number and caption sit in a box inside the ring's
/// hole; at accessibility text sizes the caption moves below the ring.
struct Ring: View {
    var value: Double              // 0...1
    var accent: Accent
    var lineWidth: CGFloat = 14
    var label: String
    var caption: String? = nil
    var size: CGFloat = 132
    /// What VoiceOver reads. Defaults to "caption: label" ("Recovery: 82";
    /// a cycle caption "Day of ~29" reads "Day 22 of about 29").
    var accessibilityText: String? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    private var spokenText: String {
        if let accessibilityText { return accessibilityText }
        guard let caption, !caption.isEmpty else { return label }
        if caption.hasPrefix("Day of ") {
            let rest = caption.dropFirst("Day of ".count).replacingOccurrences(of: "~", with: "about ")
            return "Day \(label) of \(rest)"
        }
        return "\(caption): \(label)"
    }

    private var ringSize: CGFloat { size * min(max(textScale, 1), 1.3) }
    private var stroke: CGFloat { lineWidth * ringSize / size }
    private var hole: CGFloat { max(ringSize - 2 * stroke, 1) }
    private var captionInside: Bool { !typeSize.isAccessibilitySize }
    /// The number's design size: the same share of the hole as before the
    /// stroke moved inside the frame.
    private var numberSize: CGFloat { (size - lineWidth) * 0.34 }

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack {
                Circle().inset(by: stroke / 2)
                    .stroke(accent.track(scheme), lineWidth: stroke)
                Circle().inset(by: stroke / 2)
                    .trim(from: 0, to: max(0.001, min(value, 1)))
                    .stroke(LinearGradient(colors: [accent.ink(scheme).opacity(scheme == .dark ? 1 : 0.7), accent.fill(scheme)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .motion(.fill, value: value)
                // A wide box that fits in the hole (the number is one line),
                // so nothing sits on the stroke. The number shrinks to fit
                // rather than being cut off with "…".
                VStack(spacing: Space.xxs) {
                    Text(label)
                        .font(.system(size: min(Font.scaledSize(numberSize), numberSize * 1.6), weight: .bold, design: .rounded)
                            .monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.15)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .motion(.fill, value: label)
                    if let caption, captionInside {
                        captionText(caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }
                }
                .frame(width: hole * 0.84, height: hole * 0.62)
            }
            .frame(width: ringSize, height: ringSize)
            if let caption, !captionInside {
                captionText(caption)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: max(ringSize, 160))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private func captionText(_ caption: String) -> some View {
        Text(caption.uppercased())
            .font(.scaled(size: 11, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(accent.ink(scheme))
    }
}

/// A tile with a title, a big value and a note. Used in grids, where it
/// fills its cell so every tile in a row is the same height. A neutral card
/// with the accent on its icon only, so a grid of tiles doesn't spend the
/// screen's colour budget (Tanaka F5).
struct MetricTile: View {
    var title: String
    var value: String
    var note: String? = nil
    var accent: Accent
    var systemImage: String? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(title).font(.bodyEmphasis)
                Spacer(minLength: 0)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.scaled(size: 15, weight: .semibold))
                        .foregroundStyle(accent.ink(scheme))
                        .accessibilityHidden(true)
                }
            }
            Text(value)
                .font(.numberL)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .motion(.fill, value: value)
            if let note { Text(note).font(.secondary).foregroundStyle(Palette(scheme: scheme).secondary) }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tileSurface()
    }
}

extension View {
    /// The neutral card surface for tiles: the card colour, its hairline
    /// border and, in light mode, the card's faint shadow.
    func tileSurface() -> some View { modifier(TileSurface()) }
}

private struct TileSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let p = Palette(scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
        content
            .background(p.card, in: shape)
            .overlay(shape.strokeBorder(p.cardBorder))
            .shadow(color: scheme == .light ? Color(hex: 0x141428, alpha: 0.06) : .clear, radius: 1, y: 1)
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
            HStack(spacing: Space.m) {
                Image(systemName: systemImage)
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(accent.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    // Decorative: VoiceOver read "Question Mark In A Filled
                    // Speech Bubble" before the title (F12).
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).font(.bodyEmphasis)
                    if let subtitle { Text(subtitle).font(.secondary).foregroundStyle(Palette(scheme: scheme).secondary) }
                }
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Palette(scheme: scheme).tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Sizes.minTap)
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
        let shape = RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
        Button(action: action) {
            Text(title)
                .font(.bodyEmphasis)
                .frame(maxWidth: .infinity, minHeight: Sizes.minTap)
                .padding(.horizontal, Space.s)
                .foregroundStyle(selected ? selectedText : p.primary)
                .background(selected ? selectedFill : p.chip, in: shape)
                .overlay(shape.strokeBorder(selected ? selectedFill : p.cardBorder))
                .motion(.select, value: selected)
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: selected) { _, isSelected in isSelected }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // Light: white on the deep ink (5:1 or better for every accent).
    // Dark: near-black on the bright fill (6:1 or better).
    private var selectedFill: Color { scheme == .dark ? accent.fill(.dark) : accent.ink(.light) }
    private var selectedText: Color { scheme == .dark ? Color(hex: 0x1A0E00) : .white }
}

/// The big rounded primary button. When `done` turns on ("Saved"), the
/// label swaps with a checkmark and a success haptic.
struct PrimaryButton: View {
    var title: String
    var accent: Accent = .indigo
    var done = false
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                if done {
                    Image(systemName: "checkmark")
                        .font(.scaled(size: 15, weight: .bold))
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .contentTransition(.opacity)
            }
            .font(.cardTitle)
            .frame(maxWidth: .infinity, minHeight: Sizes.tallRow)
            .foregroundStyle(done ? Accent.mint.ink(scheme) : (scheme == .dark ? Color(hex: 0x0E1136) : .white))
            .background(done ? Accent.mint.tint(scheme) : (scheme == .dark ? accent.ink(.dark) : accent.ink(.light)),
                        in: Capsule())
            .motion(.select, value: done)
            .motion(.select, value: title)
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.success, trigger: done) { old, new in !old && new }
    }
}

extension View {
    /// A text link ("Learn how we got this number", "Skip"): a 44pt-tall
    /// tap target that only takes the height of its text in the layout.
    func textLinkHitArea() -> some View {
        frame(minHeight: Sizes.minTap)
            .contentShape(Rectangle())
            .padding(.vertical, -12)
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
                .font(.scaled(size: 11, weight: .bold))
                .foregroundStyle((ok ? Accent.mint : Accent.coral).ink(scheme))
                .frame(width: 22, height: 22)
                .background((ok ? Accent.mint : Accent.coral).tint(scheme), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.bodyEmphasis)
                Text(detail).font(.secondary).foregroundStyle(Palette(scheme: scheme).secondary)
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
                    .motion(.fill, value: fraction)
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

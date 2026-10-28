import SwiftUI

// Rows that put the details one tap down: `MetricRow` (a number that
// opens a page), `ExpandRow` (text that opens in place), both stacked in a
// `RowCard` with `RowDivider`s between them. Every row is at least 56pt
// tall, the whole row is the tap target, and at accessibility text sizes
// the trailing value moves under the title instead of squeezing it.

/// A card that holds a list of rows edge to edge: no padding of its own,
/// no gap between rows (each row pads itself). Put `RowDivider()` between
/// rows. Use it for 2 to 5 `MetricRow`s or `ExpandRow`s.
struct RowCard<Content: View>: View {
    var accent: Accent? = nil
    @ViewBuilder var content: Content

    var body: some View {
        Card(accent: accent, padding: 0) {
            VStack(alignment: .leading, spacing: 0) { content }
        }
    }
}

/// The hairline between rows in a `RowCard`, inset to line up with the
/// row titles (64pt: padding, icon tile and gap), or from the card's edge
/// padding when the rows have no icon.
struct RowDivider: View {
    var hasIcon = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Divider()
            .overlay(Palette(scheme: scheme).cardBorder)
            .padding(.leading, hasIcon ? Space.l + Sizes.icon + Space.m : Space.l)
    }
}

/// The rounded-square icon at the start of a row.
struct RowIcon: View {
    var systemImage: String
    var accent: Accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.scaled(size: 16, weight: .semibold))
            .foregroundStyle(accent.ink(scheme))
            .frame(width: Sizes.icon, height: Sizes.icon)
            .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A word under a row's value that says how it reads ("Usual", "Low"),
/// in its accent's ink.
struct RowVerdict: Hashable {
    var text: String
    var accent: Accent
}

/// The compact metric row (the Body tab's vitals row, shared): icon tile,
/// title and a one-line note, then the value, a verdict word under it and
/// a chevron. The whole row pushes `destination` (or runs `action`).
///
/// Use it for anything that has a number and a page behind it: vitals,
/// "Sleep debt · 4h 36m", "History". The trailing `value` is a numeral or a
/// time only ("43 ms", "4h 36m"); if the answer is a word, put it in `note`
/// (or `verdict`) and leave `value` nil, so it never wraps to two lines.
/// Stack 2 to 5 in a `RowCard` with `RowDivider`s.
struct MetricRow<Destination: View>: View {
    var title: String
    var note: String? = nil
    var value: String? = nil
    var verdict: RowVerdict? = nil
    var trend: RowTrend? = nil
    var systemImage: String
    var accent: Accent
    private var destination: Destination?
    private var action: (() -> Void)?

    /// A row that pushes `destination`.
    init(title: String, note: String? = nil, value: String? = nil, verdict: RowVerdict? = nil,
         trend: RowTrend? = nil, systemImage: String, accent: Accent,
         @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.note = note
        self.value = value
        self.verdict = verdict
        self.trend = trend
        self.systemImage = systemImage
        self.accent = accent
        self.destination = destination()
        self.action = nil
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { label }
            } else if let destination {
                NavigationLink { destination } label: { label }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, value, verdict?.text, note].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }

    private var label: some View {
        MetricRowLabel(title: title, note: note, value: value, verdict: verdict, trend: trend,
                       systemImage: systemImage, accent: accent)
    }
}

extension MetricRow where Destination == EmptyView {
    /// A row that runs `action` (opens a sheet, switches a tab).
    init(title: String, note: String? = nil, value: String? = nil, verdict: RowVerdict? = nil,
         trend: RowTrend? = nil, systemImage: String, accent: Accent, action: @escaping () -> Void) {
        self.title = title
        self.note = note
        self.value = value
        self.verdict = verdict
        self.trend = trend
        self.systemImage = systemImage
        self.accent = accent
        self.destination = nil
        self.action = action
    }
}

/// What a `MetricRow` draws, for rows wrapped in a custom control.
struct MetricRowLabel: View {
    var title: String
    var note: String? = nil
    var value: String? = nil
    var verdict: RowVerdict? = nil
    var trend: RowTrend? = nil
    var systemImage: String
    var accent: Accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let p = Palette(scheme: scheme)
        let ax = typeSize.isAccessibilitySize
        HStack(alignment: ax ? .top : .center, spacing: Space.m) {
            RowIcon(systemImage: systemImage, accent: accent)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                    .font(.bodyEmphasis)
                    .lineLimit(ax ? nil : 1)
                    .minimumScaleFactor(ax ? 1 : 0.8)
                if ax { trailing(p, ax: true) }
                if let note { noteLine(note, p, ax: ax) }
            }
            Spacer(minLength: Space.s)
            if !ax { trailing(p, ax: false) }
            Image(systemName: "chevron.right")
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(p.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, minHeight: Sizes.tallRow, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func trailing(_ p: Palette, ax: Bool) -> some View {
        if value != nil || verdict != nil {
            VStack(alignment: ax ? .leading : .trailing, spacing: 0) {
                if let value {
                    Text(value)
                        .font(.numberM)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let verdict {
                    Text(verdict.text)
                        .font(.secondary).fontWeight(.semibold)
                        .foregroundStyle(verdict.accent.ink(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private func noteLine(_ note: String, _ p: Palette, ax: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let trend {
                Image(systemName: trend.up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.scaled(size: 8, weight: .bold))
                    .foregroundStyle(trendColor(trend.tone, p))
                    .accessibilityHidden(true)
            }
            Text(note)
                .font(.secondary)
                .foregroundStyle(p.secondary)
                .lineLimit(ax ? 2 : 1)
                .minimumScaleFactor(ax ? 1 : 0.9)
        }
    }

    private func trendColor(_ tone: RowTrend.Tone, _ p: Palette) -> Color {
        switch tone {
        case .worse: Accent.coral.ink(scheme)
        case .better: Accent.mint.ink(scheme)
        case .neutral: p.tertiary
        }
    }
}

/// A row that opens in place: a 56pt header with a chevron that turns
/// down when open, and the content under it. Collapsed by default.
///
/// Use it for copy that's read, not scrubbed, and fits in about 8 lines
/// or one small chart: tips, "What moved today", a list of today's logs.
/// Anything longer, or with a form or a scrub chart, is a pushed page or a
/// Health guide article instead. Several live in one `RowCard`; siblings
/// don't close each other.
///
/// `summary` is one line under the title while it's closed ("3 tips",
/// "1 drink · 130 mg"). Content defaults to body text in the secondary
/// colour. VoiceOver reads it as a button with "Expanded" / "Collapsed";
/// with Reduce Motion the content fades and the chevron doesn't turn.
struct ExpandRow<Content: View>: View {
    var title: String
    var summary: String? = nil
    var systemImage: String? = nil
    var accent: Accent = .indigo
    /// Lines the closed summary may use at the default text sizes (2 for
    /// a sentence that would otherwise be cut off mid-thought, F13).
    var summaryLines = 1
    private var external: Binding<Bool>?
    @State private var internalExpanded: Bool
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// State kept by the row itself (not remembered between visits).
    init(title: String, summary: String? = nil, summaryLines: Int = 1, systemImage: String? = nil,
         accent: Accent = .indigo, initiallyExpanded: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.summaryLines = summaryLines
        self.systemImage = systemImage
        self.accent = accent
        self.external = nil
        self._internalExpanded = State(initialValue: initiallyExpanded)
        self.content = content()
    }

    /// State owned by the screen (to open one from elsewhere).
    init(title: String, summary: String? = nil, systemImage: String? = nil, accent: Accent = .indigo,
         isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.accent = accent
        self.external = isExpanded
        self._internalExpanded = State(initialValue: false)
        self.content = content()
    }

    private var isExpanded: Binding<Bool> { external ?? $internalExpanded }

    var body: some View {
        let p = Palette(scheme: scheme)
        let open = isExpanded.wrappedValue
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withMotion(.reveal) { isExpanded.wrappedValue.toggle() }
            } label: {
                header(p, open: open)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([title, open ? nil : summary].compactMap { $0 }.joined(separator: ", "))
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(open ? "Hides the details" : "Shows the details")
            if open {
                VStack(alignment: .leading, spacing: Space.s) { content }
                    .font(.role(.bodyText))
                    .foregroundStyle(p.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, systemImage == nil ? Space.l : Space.l + Sizes.icon + Space.m)
                    .padding(.trailing, Space.l)
                    .padding(.bottom, Space.l)
                    .motionTransition(.reveal, edge: .top)
            }
        }
        .clipped()
    }

    private func header(_ p: Palette, open: Bool) -> some View {
        let ax = typeSize.isAccessibilitySize
        return HStack(alignment: ax ? .top : .center, spacing: Space.m) {
            if let systemImage { RowIcon(systemImage: systemImage, accent: accent) }
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                    .font(.bodyEmphasis)
                    .foregroundStyle(p.primary)
                    .lineLimit(ax ? nil : 1)
                    .minimumScaleFactor(ax ? 1 : 0.8)
                if let summary, !open {
                    Text(summary)
                        .font(.secondary)
                        .foregroundStyle(p.secondary)
                        .lineLimit(ax ? max(2, summaryLines) : summaryLines)
                        .minimumScaleFactor(ax ? 1 : 0.9)
                }
            }
            Spacer(minLength: Space.s)
            Image(systemName: "chevron.right")
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(p.tertiary)
                .rotationEffect(.degrees(open && !reduceMotion ? 90 : 0))
                // With Reduce Motion the chevron swaps instead of turning.
                .opacity(open && reduceMotion ? 0 : 1)
                .overlay {
                    if open && reduceMotion {
                        Image(systemName: "chevron.down")
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(p.tertiary)
                    }
                }
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, minHeight: Sizes.tallRow, alignment: .leading)
        .contentShape(Rectangle())
    }
}

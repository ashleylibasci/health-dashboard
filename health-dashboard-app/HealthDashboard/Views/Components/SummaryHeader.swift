import SwiftUI
import HealthCore

// The layout every screen follows (structure review, Oct 28: Marín 1.7):
//
//   Screen(title:, accent:)            nav title only, no title in the body
//     SampleDataBanner()               the small "Example data" capsule
//     [CalloutBar]                     only while its trigger is true, at most one
//     SummaryHeader                    the 2-second answer, ≤ 160pt
//     one chart card                   ≤ 280pt, readout with `detailSlots`;
//                                      inside: readout, plot, axis, a one-line
//                                      legend, then `ScrubHint` (shown until
//                                      her first scrub, D-G1)
//     RowCard { ExpandRow / MetricRow … }   ≤ 5 rows: details, history, drivers
//     Card(density: .compact) { LearnMoreRow }   "Learn more about X", last
//
// Detail screens link down, never sideways. Long copy moves to an ⓘ sheet
// (1 to 2 paragraphs), an ExpandRow (peeked at often, ≤ 8 lines), or a
// pushed page / Health guide article (a chart, a form, or more than that).

/// The 2-second answer at the top of a screen: an eyebrow, one big value or
/// verdict, one sentence, and at most two stat pairs, in one tinted card.
///
/// Use it once per screen, first (after the example-data capsule and any
/// `CalloutBar`). It's the only card with a CAPS eyebrow. Keep it under
/// 160pt at the default text size: one sentence, no paragraphs, no ring.
///
/// - `value` is a number or time ("130", "7h 21m") in the display role; a
///   verdict word ("No signs") drops to the heading role automatically.
/// - At accessibility text sizes the unit and status move under the value
///   and the stat pairs stack.
/// - `footer` is for one `LearnMoreRow` (after a divider), nothing else.
struct SummaryHeader<Footer: View>: View {
    var eyebrow: String
    var value: String
    var unit: String? = nil
    var status: SummaryStatus? = nil
    var line: String
    var pairs: [StatPair] = []
    var accent: Accent
    var info: Explanation? = nil
    @ViewBuilder var footer: Footer
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// "7h 21m", "43 ms", or the verdict word.
    private var pinnedAnswer: String {
        guard valueIsNumber, let unit else { return value }
        return "\(value) \(unit)"
    }

    /// Numerals and times get the big display role; words don't.
    private var valueIsNumber: Bool { value.contains { $0.isNumber } }

    private var spoken: String {
        var parts = ["\(eyebrow): \(value)\(unit.map { " \($0)" } ?? "")"]
        if let status { parts.append(status.text) }
        parts.append(line)
        parts += pairs.map { "\($0.label): \($0.value)" }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        let ax = typeSize.isAccessibilitySize
        Card(accent: accent) {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: 0) {
                    CapsLabel(eyebrow, color: accent.ink(scheme))
                    Spacer(minLength: Space.s)
                    if let info {
                        InfoButton(explanation: info)
                            .padding(.vertical, -10)
                            .padding(.trailing, -12)
                    }
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    AdaptiveStack(spacing: ax ? Space.xs : Space.s, alignment: .firstTextBaseline) {
                        Text(value)
                            .font(valueIsNumber ? .display : .heading)
                            .lineLimit(ax ? 2 : 1)
                            .minimumScaleFactor(0.6)
                        if let unit {
                            Text(unit)
                                .font(.bodyEmphasis)
                                .foregroundStyle(p.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        if !ax { Spacer(minLength: Space.s) }
                        if let status { StatusChip(status: status) }
                    }
                    // Joins the title in the bar once scrolled away (D-M5).
                    .pinsAnswer(pinnedAnswer)
                    Text(line)
                        .font(.bodyText)
                        .foregroundStyle(p.secondary)
                        .lineLimit(ax ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !pairs.isEmpty {
                        AdaptiveStack(spacing: Space.m, alignment: .top) {
                            ForEach(pairs.prefix(2)) { pair in
                                StatPairView(pair: pair)
                                    .frame(maxWidth: ax ? nil : .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, Space.xs)
                    }
                }
                // One element: VoiceOver reads the answer in one go.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
            }
            footer
        }
    }
}

extension SummaryHeader where Footer == EmptyView {
    init(eyebrow: String, value: String, unit: String? = nil, status: SummaryStatus? = nil, line: String,
         pairs: [StatPair] = [], accent: Accent, info: Explanation? = nil) {
        self.init(eyebrow: eyebrow, value: value, unit: unit, status: status, line: line, pairs: pairs,
                  accent: accent, info: info) { EmptyView() }
    }
}

/// The verdict chip on a `SummaryHeader`'s trailing edge ("Take it steady").
struct SummaryStatus: Hashable {
    var text: String
    var accent: Accent
}

/// A small label over a value, side by side in a `SummaryHeader`.
struct StatPair: Identifiable, Hashable {
    var id: String { label }
    var label: String
    var value: String
}

/// One `StatPair`: a CAPS label over a card-title value on one line.
struct StatPairView: View {
    var pair: StatPair

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            CapsLabel(pair.label, isHeader: false)
            Text(pair.value)
                .font(.cardTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// A one-word or short-phrase status in a tinted capsule. Never wraps.
struct StatusChip: View {
    var status: SummaryStatus
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(status.text)
            .font(.bodyEmphasis)
            .foregroundStyle(status.accent.onTint(scheme))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Space.s + 2)
            .padding(.vertical, Space.xs)
            .background(status.accent.fill(scheme).opacity(0.2), in: Capsule())
    }
}

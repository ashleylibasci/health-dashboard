import SwiftUI
import Charts

/// How far back a nightly trend chart looks (D-G2), like Apple Health's
/// W / M / 6M: a week or a month of nights, or six months of weekly
/// averages. On HRV, resting heart rate and sleep.
enum TrendRange: String, CaseIterable, Hashable {
    case week, month, sixMonths

    /// The segment: "W", "M", "6M".
    var short: String {
        switch self {
        case .week: "W"
        case .month: "M"
        case .sixMonths: "6M"
        }
    }

    /// What VoiceOver reads for the segment, and the chip at large text sizes.
    var spoken: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .sixMonths: "6 months"
        }
    }

    /// "Last 7 nights", "Last 30 nights", "Last 6 months".
    var title: String {
        switch self {
        case .week: "Last 7 nights"
        case .month: "Last 30 nights"
        case .sixMonths: "Last 6 months"
        }
    }

    /// Six months is too many nights to read one by one, so it shows one
    /// point per week.
    var isWeekly: Bool { self == .sixMonths }

    /// "night" or "week", for "Drag across the chart to see each …".
    var step: String { isWeekly ? "week" : "night" }

    /// The wake days the chart spans, ending today: the last 7 or 30 days, or
    /// the 26 calendar weeks up to this one.
    func domain(now: Date = .now, calendar cal: Calendar = .current) -> ClosedRange<Date> {
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        switch self {
        case .week: return (cal.date(byAdding: .day, value: -6, to: today) ?? today)...tomorrow
        case .month: return (cal.date(byAdding: .day, value: -29, to: today) ?? today)...tomorrow
        case .sixMonths:
            let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            let start = cal.date(byAdding: .weekOfYear, value: -25, to: thisWeek) ?? thisWeek
            return start...(cal.date(byAdding: .weekOfYear, value: 1, to: thisWeek) ?? tomorrow)
        }
    }

    /// The x unit marks are placed on.
    var unit: Calendar.Component { isWeekly ? .weekOfYear : .day }
}

/// One point on a weekly chart: the average of the nights in a calendar week.
struct WeeklyAverage: Hashable {
    /// Midnight starting the week.
    let week: Date
    let value: Double
    let nights: Int

    /// Nights a week needs before it gets a point: one or two nights would
    /// make a week look better or worse than it was.
    static let nightsNeeded = 3

    /// Averages `values` by calendar week, oldest first, leaving out weeks
    /// with fewer than `nightsNeeded` nights.
    static func by<Item>(_ items: [Item], date: (Item) -> Date, value: (Item) -> Double,
                         calendar cal: Calendar = .current) -> [WeeklyAverage] {
        let groups = Dictionary(grouping: items) { cal.dateInterval(of: .weekOfYear, for: date($0))?.start ?? date($0) }
        return groups.compactMap { week, members in
            guard members.count >= nightsNeeded else { return nil }
            let mean = members.map(value).reduce(0, +) / Double(members.count)
            return WeeklyAverage(week: week, value: mean, nights: members.count)
        }
        .sorted { $0.week < $1.week }
    }
}

/// The W / M / 6M control for a trend chart.
struct TrendRangePicker: View {
    @Binding var range: TrendRange
    var accent: Accent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the chips have room for the words.
        AdaptiveSegmentedPicker("Range", selection: $range, options: TrendRange.allCases, accent: accent,
                                spoken: { $0.spoken }) { typeSize.isAccessibilitySize ? $0.spoken : $0.short }
    }
}

/// Her break weeks, shaded behind a trend chart (D-G3). Spans come from
/// `AppModel.breakSpans(in:)`; none when she isn't on the pill.
struct BreakWeekMarks: ChartContent {
    let spans: [ClosedRange<Date>]
    let scheme: ColorScheme
    /// The y domain to fill, for bar charts (where a band without one stops
    /// short of the bars' baseline).
    var height: ClosedRange<Double>? = nil

    var body: some ChartContent {
        ForEach(spans, id: \.lowerBound) { span in
            if let height {
                RectangleMark(xStart: .value("Break starts", span.lowerBound), xEnd: .value("Break ends", span.upperBound),
                              yStart: .value("Bottom", height.lowerBound), yEnd: .value("Top", height.upperBound))
                    .foregroundStyle(ChartKey.breakFill(scheme))
            } else {
                RectangleMark(xStart: .value("Break starts", span.lowerBound), xEnd: .value("Break ends", span.upperBound))
                    .foregroundStyle(ChartKey.breakFill(scheme))
            }
        }
    }
}

/// The key under a trend chart, for what isn't labelled on the plot:
/// "Break week" for the shaded bands.
struct ChartKey: View {
    struct Item: Hashable {
        enum Mark: Hashable { case band }
        var label: String
        var mark: Mark
    }

    var items: [Item]
    @Environment(\.colorScheme) private var scheme

    /// The break-week shading, on the chart and in the key.
    static func breakFill(_ scheme: ColorScheme) -> Color {
        Accent.pink.fill(scheme).opacity(scheme == .dark ? 0.13 : 0.11)
    }

    @ViewBuilder
    private func swatch(_ item: Item) -> some View {
        switch item.mark {
        case .band:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Self.breakFill(scheme))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Accent.pink.fill(scheme).opacity(0.5)))
                .frame(width: 14, height: 12)
        }
    }

    private func spoken(_ item: Item) -> String {
        switch item.mark {
        case .band: "Shaded: \(item.label.lowercased())"
        }
    }

    var body: some View {
        FlowLayout(spacing: Space.m) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: Space.s) {
                    swatch(item)
                    Text(item.label)
                }
            }
        }
        .font(.secondary)
        .foregroundStyle(Palette(scheme: scheme).secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map(spoken).joined(separator: ". "))
    }
}

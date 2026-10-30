import SwiftUI

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

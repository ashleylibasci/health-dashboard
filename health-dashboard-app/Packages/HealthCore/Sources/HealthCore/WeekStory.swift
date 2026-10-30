import Foundation

/// "Your week" as a story (D-P1): the numbers behind its cards, from the
/// same seven days as the week recap. Each part is what happened that
/// week; none of it claims a cause.
public struct WeekStory: Hashable, Sendable {
    /// The night she slept longest (the earlier bedtime on a tie).
    public var bestNight: DaySummary
    public var averageAsleep: Int
    public var averageEnergy: Int
    public var bestDay: DaySummary
    public var lowestDay: DaySummary
    /// Average energy on weekdays and on Saturday and Sunday, when the week
    /// has at least two of each; otherwise nil.
    public var weekdayEnergy: Int?
    public var weekendEnergy: Int?
    public var caffeine: Caffeine

    public struct Caffeine: Hashable, Sendable {
        /// Days with any caffeine logged.
        public var days: Int
        /// Average on those days.
        public var averageMg: Int
        /// The middle of her last-drink times (app-day minutes), nil without drinks.
        public var typicalLast: Minutes?
        /// Days whose last drink came after `cutoff`.
        public var daysAfterCutoff: Int
    }

    /// `cutoff`: her caffeine cutoff (app-day minutes), nil when none is
    /// shown. Nil under 3 days, like the recap.
    public static func make(days: [DaySummary], cutoff: Minutes?, calendar: Calendar = .current) -> WeekStory? {
        guard days.count >= 3 else { return nil }
        func avg(_ xs: [Int]) -> Int? { xs.isEmpty ? nil : Int((Double(xs.reduce(0, +)) / Double(xs.count)).rounded()) }
        let best = days.max { ($0.asleep, -$0.bedtime) < ($1.asleep, -$1.bedtime) }!
        let byEnergy = days.sorted { ($0.energy, $1.date) > ($1.energy, $0.date) }
        let weekend = days.filter { calendar.isDateInWeekend($0.date) }.map(\.energy)
        let weekday = days.filter { !calendar.isDateInWeekend($0.date) }.map(\.energy)
        let split = weekend.count >= 2 && weekday.count >= 2
        let withCaffeine = days.filter { $0.caffeineMg > 0 }
        let lasts = withCaffeine.compactMap(\.lastCaffeine).map(Double.init)
        let caffeine = Caffeine(days: withCaffeine.count, averageMg: avg(withCaffeine.map(\.caffeineMg)) ?? 0,
                                typicalLast: lasts.median.map { Int($0.rounded()) },
                                daysAfterCutoff: cutoff.map { c in withCaffeine.filter { ($0.lastCaffeine ?? 0) > c }.count } ?? 0)
        return WeekStory(bestNight: best, averageAsleep: avg(days.map(\.asleep)) ?? 0, averageEnergy: avg(days.map(\.energy)) ?? 0,
                         bestDay: byEnergy.first!, lowestDay: byEnergy.last!,
                         weekdayEnergy: split ? avg(weekday) : nil, weekendEnergy: split ? avg(weekend) : nil,
                         caffeine: caffeine)
    }
}

/// Where a week fell in her pill pack (D-P1's pack card).
public struct PackWeek: Hashable, Sendable {
    /// Pack day of the first and last day of the week.
    public var firstDay: Int
    public var lastDay: Int
    /// Days with an active pill, and how many of those she marked taken.
    public var pillDays: Int
    public var taken: Int
    /// Break days in the week.
    public var breakDays: Int
    /// The next break or new pack within a week after `today`, if any.
    public var next: Upcoming?

    public struct Upcoming: Hashable, Sendable {
        public enum Kind: Hashable, Sendable { case breakStarts, newPack }
        public var kind: Kind
        public var date: Date
    }

    /// `days`: the week's days (midnights, oldest first); `taken`: whether
    /// that day's pill is marked taken.
    public static func make(pack: PillPack, days: [Date], today: Date, taken: (Date) -> Bool,
                            calendar: Calendar = .current) -> PackWeek? {
        guard let first = days.first, let last = days.last else { return nil }
        let pillDays = days.filter { pack.isPillDay($0, calendar: calendar) }
        var next: Upcoming?
        for i in 1...7 {
            guard let d = calendar.date(byAdding: .day, value: i, to: calendar.startOfDay(for: today)) else { continue }
            let n = pack.day(on: d, calendar: calendar)
            if n == 1 { next = Upcoming(kind: .newPack, date: d); break }
            if pack.hasBreak && n == pack.activeDays + 1 { next = Upcoming(kind: .breakStarts, date: d); break }
        }
        return PackWeek(firstDay: pack.day(on: first, calendar: calendar), lastDay: pack.day(on: last, calendar: calendar),
                        pillDays: pillDays.count, taken: pillDays.filter(taken).count,
                        breakDays: days.count - pillDays.count, next: next)
    }
}

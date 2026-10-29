import Foundation

/// When her pill packs run out and when to remind her to refill (H-A6).
/// Running out over a break is a common way students end up starting a pack
/// late, the riskiest miss.
public struct PillRefill: Hashable, Sendable {
    /// Midnight of pill 1 of the pack she was on when she counted.
    public var countedFrom: Date
    /// Packs she had then, counting that one.
    public var packs: Int
    public var packLength: Int

    /// Days before she runs out that the reminder comes.
    public static let leadDays = 7
    /// The reminder's time of day, minutes after midnight (10am).
    public static let reminderTime: Minutes = 10 * 60

    public init(countedFrom: Date, packs: Int, packLength: Int) {
        self.countedFrom = countedFrom
        self.packs = max(packs, 0)
        self.packLength = max(packLength, 1)
    }

    /// The day she needs a pack she doesn't have: pill 1 after the last one.
    public func refillBy(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: packs * packLength, to: calendar.startOfDay(for: countedFrom)) ?? countedFrom
    }

    /// Packs left on `date`, counting the one she's on (0 once they've run out).
    public func packsLeft(on date: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: countedFrom),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return max(packs - max(days, 0) / packLength, 0)
    }

    /// A week before she runs out, at 10am. When the refill date falls in
    /// Thanksgiving or winter break, a week before the break starts instead,
    /// so she picks up before she leaves campus.
    public func reminder(calendar: Calendar = .current) -> Date {
        let by = refillBy(calendar: calendar)
        let day = Self.campusBreak(containing: by, calendar: calendar)?.start ?? by
        let remindDay = calendar.date(byAdding: .day, value: -Self.leadDays, to: day) ?? day
        // Wall-clock, so a clock-change day still means 10am.
        return calendar.date(bySettingHour: Self.reminderTime / 60, minute: Self.reminderTime % 60, second: 0, of: remindDay) ?? remindDay
    }

    /// The US college breaks most likely to strand her without a pack:
    /// Thanksgiving (the Saturday before through the Sunday after) and
    /// winter break (Dec 13 – Jan 15, wide enough for most schools).
    public static func campusBreak(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        var breaks: [DateInterval] = []
        if let thanksgiving = calendar.date(from: DateComponents(year: year, month: 11, weekday: 5, weekdayOrdinal: 4)),
           let start = calendar.date(byAdding: .day, value: -5, to: thanksgiving),
           let end = calendar.date(byAdding: .day, value: 4, to: thanksgiving) {
            breaks.append(DateInterval(start: start, end: end))
        }
        for y in [year - 1, year] {
            if let start = calendar.date(from: DateComponents(year: y, month: 12, day: 13)),
               let end = calendar.date(from: DateComponents(year: y + 1, month: 1, day: 16)) {
                breaks.append(DateInterval(start: start, end: end))
            }
        }
        return breaks.first { $0.start <= day && day < $0.end }
    }
}

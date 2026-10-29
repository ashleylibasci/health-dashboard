import Foundation

/// "Your mood by pack day" (H-B1): daily 1–5 ratings laid on her pack, so a
/// pattern across packs (the DRSP way: daily ratings over time) shows apart
/// from one bad week.
public struct MoodByPackDay: Hashable, Sendable {
    /// One rated day.
    public struct Point: Hashable, Sendable {
        public var pack: Int
        public var day: Int
        public var value: Int
    }
    public var points: [Point]
    /// Pack day → the average of her ratings on that day across packs.
    public var averages: [Int: Double]
    /// Packs with at least `daysPerPack` rated days.
    public var packsCovered: Int

    /// Rated days a pack needs before it counts toward the chart.
    public static let daysPerPack = 10
    /// Packs needed before the chart shows ("after two packs").
    public static let packsNeeded = 2

    public var isReady: Bool { packsCovered >= Self.packsNeeded }

    /// The average over active-pill days and over break days.
    public func split(activeDays: Int) -> (active: Double?, breakDays: Double?) {
        let active = points.filter { $0.day <= activeDays }.map { Double($0.value) }
        let brk = points.filter { $0.day > activeDays }.map { Double($0.value) }
        return (active.mean, brk.mean)
    }

    /// `ratings`: one value per day (midnight), 1–5.
    public static func make(_ ratings: [Date: Int], in calendar: PackCalendar, since: Date? = nil,
                            cal: Calendar = .current) -> MoodByPackDay {
        let points = ratings.compactMap { day, value -> Point? in
            if let since, day < cal.startOfDay(for: since) { return nil }
            let at = calendar.position(of: day, calendar: cal)
            return Point(pack: at.pack, day: at.day, value: value)
        }.sorted { ($0.pack, $0.day) < ($1.pack, $1.day) }
        let byDay = Dictionary(grouping: points, by: \.day)
        let averages = byDay.mapValues { ps in Double(ps.map(\.value).reduce(0, +)) / Double(ps.count) }
        let perPack = Dictionary(grouping: points, by: \.pack).values.filter { $0.count >= daysPerPack }.count
        return MoodByPackDay(points: points, averages: averages, packsCovered: perPack)
    }
}

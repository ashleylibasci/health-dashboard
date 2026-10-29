import Foundation

/// Her packs going back in time: which pack and which pack day any past
/// date fell on, counting whole packs back from the current pack's start.
/// The pill-history features (bleeds by pack, mood by pack day, break-week
/// patterns, pack-day baselines, the visit summary) all read past days
/// through this, so they agree on where each pack began.
///
/// It assumes the same pack type all the way back (`PillPack` only knows
/// the current one), so callers count only days since her last method
/// change.
public struct PackCalendar: Hashable, Sendable {
    /// Midnight of pill 1 of any pack (the current one is easiest).
    public var start: Date
    public var activeDays: Int
    public var packLength: Int

    public init(start: Date, activeDays: Int, packLength: Int) {
        self.start = start
        self.packLength = max(packLength, 1)
        self.activeDays = min(max(activeDays, 1), self.packLength)
    }

    public init(_ pack: PillPack) {
        self.init(start: pack.start, activeDays: pack.activeDays, packLength: pack.packLength)
    }

    public var hasBreak: Bool { activeDays < packLength }

    /// Where `date` falls: `pack` counts packs from `start` (0 is the pack
    /// that starts there, −1 the one before), `day` is 1…packLength.
    public struct Position: Hashable, Sendable {
        public var pack: Int
        public var day: Int
        public init(pack: Int, day: Int) { self.pack = pack; self.day = day }
    }

    public func position(of date: Date, calendar: Calendar = .current) -> Position {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        let pack = Int((Double(days) / Double(packLength)).rounded(.down))
        return Position(pack: pack, day: days - pack * packLength + 1)
    }

    /// A break day (no active pill).
    public func isBreak(day: Int) -> Bool { day > activeDays }

    /// Midnight of pill 1 of `pack`.
    public func start(ofPack pack: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: pack * packLength, to: calendar.startOfDay(for: start)) ?? start
    }

    /// Midnight of `day` in `pack`.
    public func date(pack: Int, day: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: pack * packLength + day - 1, to: calendar.startOfDay(for: start)) ?? start
    }

    /// The packs that have ended by `now` and began on or after `since`
    /// (her method change), most recent last.
    public func finishedPacks(since: Date?, now: Date, calendar: Calendar = .current) -> [Int] {
        let current = position(of: now, calendar: calendar).pack
        let first = since.map { s -> Int in
            let p = position(of: s, calendar: calendar)
            return p.day == 1 ? p.pack : p.pack + 1
        } ?? Int.min
        guard first < current else { return [] }
        return Array(max(first, current - 24)..<current)
    }
}

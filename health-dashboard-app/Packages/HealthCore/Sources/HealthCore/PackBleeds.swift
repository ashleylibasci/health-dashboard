import Foundation

/// Bleeds over time (H-A10): for each pack, the withdrawal bleed (how many
/// days, the heaviest flow) and any bleeding or spotting on active pills.
/// A run of logged days that touches the break is that pack's withdrawal
/// bleed, even where it runs into the next pack's first pills; other runs
/// are breakthrough bleeding.
public enum PackBleeds {
    /// Flow levels as the app logs them.
    public enum Level: Int, Comparable, Sendable {
        case spotting = 1, light, medium, heavy
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Pack: Hashable, Sendable {
        public var pack: Int
        /// Days of the withdrawal bleed, spotting included; 0 when none was logged.
        public var bleedDays: Int
        public var heaviest: Level?
        /// Pack days 1… of the bleed's days and their levels, for the dots.
        public var days: [Int: Level]
        /// Active-pill days with bleeding or spotting.
        public var activeDays: Int
    }

    /// `flows`: one level per logged day (later entries win). Only packs in
    /// `packs` are returned, in that order.
    public static func summarize(_ flows: [(date: Date, level: Level)], packs: [Int], in calendar: PackCalendar,
                                 cal: Calendar = .current) -> [Pack] {
        var byDay: [Date: Level] = [:]
        for f in flows { byDay[cal.startOfDay(for: f.date)] = f.level }
        var out = Dictionary(uniqueKeysWithValues: packs.map { ($0, Pack(pack: $0, bleedDays: 0, heaviest: nil, days: [:], activeDays: 0)) })
        // Runs of consecutive logged days.
        var runs: [[Date]] = []
        for day in byDay.keys.sorted() {
            if let last = runs.last?.last, cal.dateComponents([.day], from: last, to: day).day == 1 {
                runs[runs.count - 1].append(day)
            } else {
                runs.append([day])
            }
        }
        for run in runs {
            let positions = run.map { calendar.position(of: $0, calendar: cal) }
            if let breakDay = positions.first(where: { calendar.isBreak(day: $0.day) }) {
                guard var p = out[breakDay.pack] else { continue }
                for (day, pos) in zip(run, positions) {
                    guard let level = byDay[day] else { continue }
                    p.bleedDays += 1
                    p.heaviest = max(p.heaviest ?? level, level)
                    // Days into the next pack carry on past the pack's length.
                    p.days[pos.pack == breakDay.pack ? pos.day : calendar.packLength + pos.day] = level
                }
                out[breakDay.pack] = p
            } else {
                for pos in positions { out[pos.pack]?.activeDays += 1 }
            }
        }
        return packs.compactMap { out[$0] }
    }
}

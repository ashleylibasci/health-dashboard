import Foundation

/// A combined-pill pack laid out on the calendar: which pill each day is,
/// which days have a pill to take, and when a new pack starts (H-A1).
public struct PillPack: Hashable, Sendable {
    /// Midnight of the day she took pill 1 of this pack. A day still ahead
    /// means she's skipping the break: the days before it count on as
    /// active pills.
    public var start: Date
    /// 21 for 21+7, 24 for 24+4, 28 for continuous use.
    public var activeDays: Int
    public var packLength: Int

    public init(start: Date, activeDays: Int, packLength: Int) {
        self.start = start
        self.packLength = max(packLength, 1)
        self.activeDays = min(max(activeDays, 1), self.packLength)
    }

    public var hasBreak: Bool { activeDays < packLength }

    /// The pack day (1…packLength) on the calendar day of `date`.
    public func day(on date: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if days < 0 { return max(1, activeDays + 1 + days) }
        return days % packLength + 1
    }

    /// A day with an active pill to take (not a break day).
    public func isPillDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        day(on: date, calendar: calendar) <= activeDays
    }

    /// Pill 1 of a pack: the riskiest one to start late, because a late
    /// start stretches the hormone-free week (CDC US SPR 2024).
    public func isNewPackDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        day(on: date, calendar: calendar) == 1
    }
}

/// Which day's pill a dose counts for.
public enum PillDay {
    /// The calendar day whose pill time is nearest the dose: from 12 hours
    /// before the pill time to 12 hours after it. With a 9pm pill time, a
    /// dose at 8:50pm or at 1am counts for that evening, and one at 9:30am
    /// counts for the coming evening.
    public static func day(for dose: Date, pillTime: Minutes, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: dose.addingTimeInterval(TimeInterval((720 - pillTime) * 60)))
    }
}

/// One pill notification.
public struct PillReminder: Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// At her pill time.
        case onTime
        /// Again, because she hasn't tapped Taken.
        case followUp
        /// The evening before a new pack after the break: have it ready.
        case newPackTomorrow
    }
    public var kind: Kind
    public var fire: Date
    /// Midnight of the pill day it's about.
    public var day: Date
    /// The pack day it's about (1 for a new pack).
    public var packDay: Int
    public var isNewPack: Bool { packDay == 1 && kind != .newPackTomorrow }

    public init(kind: Kind, fire: Date, day: Date, packDay: Int) {
        self.kind = kind
        self.fire = fire
        self.day = day
        self.packDay = packDay
    }
}

/// The pill reminders for the days ahead (H-A1): one at her pill time on
/// every pill day, repeated once an hour later if she hasn't taken it.
/// New-pack day gets the most: the evening before, the reminder, and two
/// repeats (30 and 60 minutes later). Nothing on break days, and nothing
/// for a day already taken.
public enum PillReminderPlan {
    /// Minutes after her pill time for the repeat on an ordinary day.
    public static let followUps = [60]
    /// …and on new-pack day.
    public static let newPackFollowUps = [30, 60]

    /// - Parameters:
    ///   - pillTime: minutes after midnight.
    ///   - isTaken: whether the pill for a day (midnight) is already taken.
    ///   - skipOnTime: Apple's Medications already reminds her at the pill
    ///     time, so only the repeats come from this app (never two at once).
    ///   - calendar: in her home time zone, so the times stay put when she
    ///     travels (H-A11).
    public static func reminders(pack: PillPack, pillTime: Minutes, now: Date, days: Int = 7,
                                 isTaken: (Date) -> Bool, skipOnTime: Bool = false,
                                 calendar: Calendar = .current) -> [PillReminder] {
        let today = calendar.startOfDay(for: now)
        var out: [PillReminder] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  // Wall-clock, so the clock-change night is still 9pm.
                  let at = calendar.date(bySettingHour: pillTime / 60, minute: pillTime % 60, second: 0, of: day) else { continue }
            let packDay = pack.day(on: day, calendar: calendar)
            if packDay <= pack.activeDays {
                guard !isTaken(day) else { continue }
                let repeats = packDay == 1 ? newPackFollowUps : followUps
                if !skipOnTime { out.append(PillReminder(kind: .onTime, fire: at, day: day, packDay: packDay)) }
                for m in repeats {
                    out.append(PillReminder(kind: .followUp, fire: at.addingTimeInterval(TimeInterval(m * 60)), day: day, packDay: packDay))
                }
            } else if let next = calendar.date(byAdding: .day, value: 1, to: day), pack.isNewPackDay(next, calendar: calendar) {
                out.append(PillReminder(kind: .newPackTomorrow, fire: at, day: next, packDay: 1))
            }
        }
        return out.filter { $0.fire > now }
    }
}

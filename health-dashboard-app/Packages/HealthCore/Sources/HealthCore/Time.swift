import Foundation

/// Minutes relative to midnight of the "wake day". A bedtime of 11:55pm the night
/// before is `-5`, 12:30am is `30`, and 8:22am is `502`. Daytime planning uses
/// plain minutes after midnight (2pm is `840`), and late evening runs past 1440.
public typealias Minutes = Int

public enum Clock {
    /// "8:22am", "12:30am", "11:55pm". Values outside 0..<1440 wrap.
    public static func format(_ minutes: Minutes, suffix: Bool = true) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        let h = m / 60
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let text = "\(hour12):" + String(format: "%02d", m % 60)
        return suffix ? text + (h < 12 ? "am" : "pm") : text
    }

    /// "7h 40m", or "35 min" under an hour. The space is non-breaking, so
    /// a line never wraps between "7h" and "40m" (design flaw 4).
    public static func duration(_ minutes: Int) -> String {
        let m = abs(minutes)
        if m < 60 { return "\(m)\u{00A0}min" }
        return "\(m / 60)h\u{00A0}" + String(format: "%02d", m % 60) + "m"
    }

    /// Minutes after midnight for a date, in the given calendar.
    public static func minutesOfDay(_ date: Date, calendar: Calendar = .current) -> Minutes {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Minutes relative to midnight of `wakeDay` (negative for the evening before),
    /// by the wall clock: whole calendar days between the two dates times 1440,
    /// plus the clock time. On a clock-change night an 8:00am wake is still 480,
    /// not 420 or 540 as elapsed seconds would give.
    public static func minutes(_ date: Date, relativeTo wakeDay: Date, calendar: Calendar = .current) -> Minutes {
        let day = calendar.startOfDay(for: date)
        let base = calendar.startOfDay(for: wakeDay)
        let days = calendar.dateComponents([.day], from: base, to: day).day ?? 0
        return days * 1440 + minutesOfDay(date, calendar: calendar)
    }

    /// The date shown on the wall clock at `minutes` relative to midnight of
    /// `wakeDay` (the inverse of `minutes(_:relativeTo:)`). A clock time that
    /// doesn't exist (spring forward) moves to the next valid time; one that
    /// happens twice (fall back) is the first of the two.
    public static func date(_ minutes: Minutes, relativeTo wakeDay: Date, calendar: Calendar = .current) -> Date {
        let dayOffset = Int((Double(minutes) / 1440).rounded(.down))
        let rest = minutes - dayOffset * 1440
        let base = calendar.startOfDay(for: wakeDay)
        let day = calendar.date(byAdding: .day, value: dayOffset, to: base) ?? base
        return calendar.date(bySettingHour: rest / 60, minute: rest % 60, second: 0, of: day,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
            ?? day.addingTimeInterval(TimeInterval(rest * 60))
    }

    /// Circular mean of clock times (handles values around midnight).
    public static func circularMean(_ values: [Minutes]) -> Minutes? {
        guard !values.isEmpty else { return nil }
        let angles = values.map { Double($0) / 1440 * 2 * .pi }
        let s = angles.map(sin).reduce(0, +), c = angles.map(cos).reduce(0, +)
        var mean = atan2(s, c) / (2 * .pi) * 1440
        if mean < 0 { mean += 1440 }
        return Int(mean.rounded())
    }
}

/// A half-open time range in minutes.
public struct TimeRange: Hashable, Codable, Sendable {
    public var start: Minutes
    public var end: Minutes
    public init(_ start: Minutes, _ end: Minutes) { self.start = start; self.end = end }
    public var length: Int { end - start }
    public func contains(_ m: Minutes) -> Bool { m >= start && m <= end }
    public var label: String {
        let a = Clock.format(start), b = Clock.format(end)
        // "10:30am–12:50pm", but "2:20–4:10pm" when both share am/pm.
        if a.suffix(2) == b.suffix(2) { return String(a.dropLast(2)) + "–" + b }
        return a + "–" + b
    }
}

public extension Array where Element == Double {
    var mean: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
    var median: Double? {
        guard !isEmpty else { return nil }
        let s = sorted()
        return count % 2 == 1 ? s[count / 2] : (s[count / 2 - 1] + s[count / 2]) / 2
    }
    var standardDeviation: Double? {
        guard count > 1, let m = mean else { return nil }
        return (map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(count - 1)).squareRoot()
    }
}

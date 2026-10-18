import Foundation

/// One asleep sample from Health, with the time zone it was recorded in.
struct SleepSample {
    var start: Date
    var end: Date
    var timeZone: TimeZone = .current
}

struct Night: Codable, Equatable {
    /// The evening the night started on, e.g. a 1am bedtime on Sat belongs to "Friday".
    var date: String
    /// 0 = Sunday … 6 = Saturday, for `date`.
    var weekday: Int
    /// Minutes after 6pm local time (so 12:35am = 395). Keeps bedtimes after midnight in order.
    var bedtime: Int
    /// Minutes after 6pm local time on the evening of `date` (so 8:30am next day = 870).
    var wake: Int
    var asleepMinutes: Int
    /// Local calendar date she woke up on.
    var wakeDate: String

    var isWeekend: Bool { weekday >= 5 }
}

/// Asleep periods more than this far apart belong to different sleeps.
private let sessionGap: TimeInterval = 2 * 60 * 60
/// Shorter sleeps are naps and don't count as the night's sleep.
private let minNight: TimeInterval = 3 * 60 * 60

/// Turns sleep-stage samples into one main sleep per night.
/// iPhone and Watch can both record the same sleep, so overlapping samples are merged
/// rather than added up.
func buildNights(_ samples: [SleepSample]) -> [Night] {
    struct Span { var start: Date; var end: Date; var startZone: TimeZone; var endZone: TimeZone }

    // Merge overlapping or touching samples into continuous asleep spans.
    var spans: [Span] = []
    for s in samples.sorted(by: { $0.start < $1.start }) {
        if var last = spans.last, s.start <= last.end {
            if s.end > last.end {
                last.end = s.end
                last.endZone = s.timeZone
            }
            spans[spans.count - 1] = last
        } else {
            spans.append(Span(start: s.start, end: s.end, startZone: s.timeZone, endZone: s.timeZone))
        }
    }

    // Group spans into sleep sessions (brief wake-ups don't split a night).
    var sessions: [[Span]] = []
    for s in spans {
        if let lastEnd = sessions.last?.last?.end, s.start.timeIntervalSince(lastEnd) <= sessionGap {
            sessions[sessions.count - 1].append(s)
        } else {
            sessions.append([s])
        }
    }

    var byDate: [String: Night] = [:]
    for session in sessions {
        let first = session.first!, last = session.last!
        let asleep = session.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        if asleep < minNight { continue }

        let bed = LocalTime(first.start, first.startZone)
        // Bedtimes before 6pm count toward the previous evening (e.g. 1am → yesterday).
        let evening = bed.minutes < 18 * 60 ? Day.shift(bed.date, -1) : bed.date
        let wake = LocalTime(last.end, last.endZone)
        let night = Night(
            date: evening,
            weekday: Day.weekday(evening),
            bedtime: bed.minutesAfter6pm(evening),
            wake: wake.minutesAfter6pm(evening),
            asleepMinutes: Int((asleep / 60).rounded()),
            wakeDate: wake.date
        )
        // If two qualifying sleeps share an evening, keep the longer one.
        if let existing = byDate[evening], existing.asleepMinutes >= night.asleepMinutes { continue }
        byDate[evening] = night
    }
    return byDate.values.sorted { $0.date < $1.date }
}

/// A wall-clock time where it was recorded, so a 1am bedtime stays 1am wherever she reads it.
private struct LocalTime {
    var date: String
    var minutes: Int

    init(_ instant: Date, _ zone: TimeZone) {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        let parts = c.dateComponents([.hour, .minute], from: instant)
        date = Day.key(instant, in: zone)
        minutes = parts.hour! * 60 + parts.minute!
    }

    func minutesAfter6pm(_ evening: String) -> Int {
        Day.between(evening, date) * 1440 + minutes - 18 * 60
    }
}

/// Formats minutes-after-6pm as a clock time, e.g. 395 → "12:35am".
func clockTime(_ minutesAfter6pm: Double) -> String {
    let total = ((Int(minutesAfter6pm.rounded()) + 18 * 60) % 1440 + 1440) % 1440
    return clockOfDay(total)
}

/// Formats minutes after midnight, e.g. 840 → "2:00pm".
func clockOfDay(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    let h12 = h % 12 == 0 ? 12 : h % 12
    return "\(h12):\(String(format: "%02d", m))\(h < 12 ? "am" : "pm")"
}

/// "7h 10m"
func hoursMinutes(_ minutes: Double) -> String {
    let m = Int(minutes.rounded())
    return "\(m / 60)h \(m % 60)m"
}

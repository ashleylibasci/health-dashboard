#if DEBUG
import Foundation

/// Made-up data for checking the screens without Apple Health: launch with `-demo`.
/// Only exists in test (Debug) builds.
enum DemoData {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func health() -> HealthData {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var samples: [SleepSample] = []
        var rhr: [String: Double] = [:], hrv: [String: Double] = [:]
        var caffeine: [String] = []
        for i in 1...77 {
            let evening = cal.date(byAdding: .day, value: -i, to: today)!
            let weekend = cal.component(.weekday, from: evening) >= 6
            let late = i % 9 == 4, afterLate = (i + 1) % 9 == 4
            let bed = cal.date(byAdding: .minute, value: (late ? 26 + i % 2 : weekend ? 25 : 24) * 60 + (i * 7) % 50, to: evening)!
            let wake = cal.date(byAdding: .minute, value: (weekend ? 34 : late ? 33 : 32) * 60 + (i * 3) % 40, to: evening)!
            samples.append(SleepSample(start: bed, end: wake))
            let morning = Day.key(cal.date(byAdding: .day, value: 1, to: evening)!)
            rhr[morning] = late ? 81 : afterLate ? 79 : 76
            hrv[morning] = late ? 36 : afterLate ? 40 : 44
            if i < 17 { caffeine.append(Day.key(evening)) }
        }
        return HealthData(nights: buildNights(samples), restingHr: rhr, hrv: hrv, caffeine: caffeine.sorted())
    }

    static func events() -> [CalendarEvent] {
        let today = Day.key(.now)
        return [
            CalendarEvent(title: "MATH 347 Midterm 1", date: Day.shift(today, -30), minutes: nil),
            CalendarEvent(title: "CS 225 Exam 1", date: Day.shift(today, -9), minutes: 19 * 60),
            CalendarEvent(title: "STAT 400 Quiz 4", date: Day.shift(today, 2), minutes: 14 * 60),
            CalendarEvent(title: "MATH 347 Midterm 2", date: Day.shift(today, 5), minutes: nil),
        ]
    }
}
#endif

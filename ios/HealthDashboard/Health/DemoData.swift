#if DEBUG
import Foundation

/// Made-up data for checking the screens without Apple Health: launch with `-demo`
/// (add `-demoSick` to see the getting-sick alert). Only exists in test (Debug) builds.
enum DemoData {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    static var sick: Bool { ProcessInfo.processInfo.arguments.contains("-demoSick") }

    static func profile() -> Profile {
        Profile(
            name: "Ashley", birthday: Calendar.current.date(byAdding: .year, value: -19, to: .now),
            cycle: ProcessInfo.processInfo.arguments.contains("-demoPill") ? .hormonal : .natural,
            birthControl: ProcessInfo.processInfo.arguments.contains("-demoPill") ? .combinedPill : nil,
            prefs: Preferences(showCalories: true, sickAlerts: true, drinksTracking: true, streaks: true),
            packStart: Calendar.current.date(byAdding: .day, value: -15, to: .now)
        )
    }

    static func health() -> HealthData {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let todayKey = Day.key(today)
        var d = HealthData()
        var samples: [SleepSample] = []
        var rng = SystemRandomNumberGenerator()
        func jitter(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }

        // Periods every 29 days; the latest started 21 days ago.
        let lastStart = Day.shift(todayKey, -21)
        let periodStarts = (0..<14).map { Day.shift(lastStart, -29 * $0) }
        func cycleDay(_ date: String) -> Int? {
            guard let start = periodStarts.filter({ $0 <= date }).max() else { return nil }
            return Day.between(start, date) + 1
        }
        for s in periodStarts { for k in 0..<5 { d.flow[Day.shift(s, k)] = k < 2 ? 3 : k < 4 ? 2 : 1 } }

        for i in 1...400 {
            let evening = cal.date(byAdding: .day, value: -i, to: today)!
            let key = Day.key(evening)
            let morning = Day.shift(key, 1)
            let weekend = cal.component(.weekday, from: evening) >= 6
            let late = i % 9 == 4, afterLate = (i + 1) % 9 == 4
            let cd = cycleDay(morning) ?? 1
            let luteal = cd > 15
            let bedMin = (late ? 26 * 60 + (i % 2) * 40 : weekend ? 25 * 60 : 24 * 60) + (i * 7) % 50
            let wakeMin = (weekend ? 34 : late ? 33 : 32) * 60 + (i * 3) % 40 - (luteal ? 15 : 0)
            let bed = cal.date(byAdding: .minute, value: bedMin, to: evening)!
            let wake = cal.date(byAdding: .minute, value: wakeMin, to: evening)!
            // Stage blocks in 90-minute cycles: core, deep (early), core, REM, with a brief wake.
            var t = bed
            var cycle = 0
            while t < wake {
                let blocks: [(SleepSample.Stage, Double)] = [(.core, 35), (.deep, cycle < 2 ? 25 : 8), (.core, 20), (.rem, 10 + Double(cycle) * 6), (.awake, cycle % 2 == 1 ? 3 : 0)]
                for (stage, minutes) in blocks where minutes > 0 {
                    let end = min(wake, t.addingTimeInterval(minutes * 60))
                    if end > t { samples.append(SleepSample(start: t, end: end, stage: stage)) }
                    t = end
                }
                cycle += 1
            }

            var rhr = 66 + (luteal ? 3 : 0) + (late ? 5 : afterLate ? 3 : 0) + jitter(-1.5...1.5)
            var hrv = 50 - (luteal ? 4 : 0) - (late ? 8 : afterLate ? 4 : 0) + jitter(-3...3)
            if i > 200 { rhr -= 4; hrv += 6 } // fitter last spring
            d.restingHr[morning] = rhr
            d.hrv[morning] = hrv
            d.wristTemp[morning] = 34.6 + (luteal ? 0.32 : 0) + jitter(-0.06...0.06)
            d.respiratory[morning] = 14.2 + jitter(-0.4...0.4)

            d.exerciseMinutes[key] = i % 3 == 0 ? 32 : i % 5 == 0 ? 22 : 9
            d.steps[key] = 6200 + Double((i * 1370) % 5200)
            d.activeKcal[key] = 300 + Double((i * 53) % 260)
            d.restingKcal[key] = 1440 + (luteal ? 70 : 0)
            d.waterMl[key] = Double(4 + i % 5) * 250

            if weekend && i % 2 == 0 {
                for k in 0..<(i % 4 == 0 ? 4 : 2) { d.drinks.append(Reading(date: cal.date(byAdding: .minute, value: 21 * 60 + k * 50, to: evening)!, value: 1)) }
                d.restingHr[morning]! += 5
                d.hrv[morning]! -= 9
            }
            if i < 30 {
                let hour = i % 4 == 0 ? 15.5 : i % 3 == 0 ? 13 : 9.6
                d.caffeineLogs.append(Reading(date: evening.addingTimeInterval(hour * 3600), value: 130))
            }
            if i % 30 == 0 { d.vo2.append(Reading(date: evening, value: (i > 200 ? 41 : 36) + jitter(-0.8...0.8))) }
            if i <= 7 { d.moods.append(Reading(date: evening.addingTimeInterval(20 * 3600), value: [0.6, 0.2, -0.4, -0.5, 0.1, 0.5, 0.3][i - 1])) }
        }

        // Today so far.
        d.caffeineLogs.append(Reading(date: today.addingTimeInterval(9.67 * 3600), value: 130))
        d.waterMl[todayKey] = 1000
        d.steps[todayKey] = 7820
        d.activeKcal[todayKey] = 260
        d.restingKcal[todayKey] = 980
        d.exerciseMinutes[todayKey] = 14
        d.restingHr[todayKey] = 70
        d.hrv[todayKey] = 43

        if sick {
            for back in 0...1 {
                let m = Day.shift(todayKey, -back)
                d.restingHr[m] = 74; d.hrv[m] = 36; d.wristTemp[m] = 35.3; d.respiratory[m] = 16.4
            }
        }

        // Hourly heart rate for 30 days: higher around afternoon deadlines.
        for back in 0..<30 {
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            for h in 7..<23 {
                let start = cal.date(byAdding: .hour, value: h, to: day)!
                if start > .now { break }
                let busy = (h == 10 || h == 15 || h == 16) ? 14.0 : 0
                d.hourlyHr[start] = 74 + busy + jitter(-4...6)
            }
        }

        d.nights = buildNights(samples)
        d.caffeineLogs.sort { $0.date < $1.date }
        d.drinks.sort { $0.date < $1.date }
        d.vo2.sort { $0.date < $1.date }
        d.moods.sort { $0.date < $1.date }
        return d
    }

    static func events() -> [CalendarEvent] {
        let today = Day.key(.now)
        return [
            CalendarEvent(title: "MATH 347 Midterm 1", date: Day.shift(today, -30), minutes: nil),
            CalendarEvent(title: "CS 225 Exam 1", date: Day.shift(today, -9), minutes: 19 * 60),
            CalendarEvent(title: "STAT 400 Quiz 4", date: Day.shift(today, 2), minutes: 14 * 60),
            CalendarEvent(title: "MATH 347 Midterm 2", date: Day.shift(today, 5), minutes: nil),
            CalendarEvent(title: "CS 225 MP due", date: Day.shift(today, -2), minutes: 23 * 60),
            CalendarEvent(title: "STAT 400 problem set due", date: Day.shift(today, -5), minutes: 17 * 60),
        ]
    }
}
#endif

import Foundation

/// The numbers whose accuracy depends on how the Watch is worn and used.
enum TrackedMetric: String, CaseIterable, Identifiable {
    case vo2, heart, sleep, wristTemp
    var id: String { rawValue }

    var title: String {
        switch self {
        case .vo2: "VO₂ max and fitness age"
        case .heart: "HRV and resting heart rate"
        case .sleep: "Sleep and sleep stages"
        case .wristTemp: "Wrist temperature"
        }
    }

    var intro: String {
        switch self {
        case .vo2: "Your Watch only estimates VO₂ max during certain workouts, so it can go weeks without updating. Everyday walks count as much as runs, as long as they’re logged."
        case .heart: "These drive your recovery score. Most readings happen while you sleep, so the more nights the Watch is on, the steadier your normal gets."
        case .sleep: "Sleep stages and wake-ups come from your Watch, and only on nights it’s on your wrist with sleep tracking on."
        case .wristTemp: "Wrist temperature helps the app spot ovulation and the getting-sick signals. It only records overnight."
        }
    }

    var tips: [(title: String, detail: String)] {
        switch self {
        case .vo2: [
            ("Log your walk to class as an Outdoor Walk", "Start one in the Workout app when you head out. Everyday walks count, not just exercise. A walk your Watch doesn’t log as a workout won’t update VO₂ max."),
            ("Aim for about 20 minutes on mostly flat ground", "Short or stop-and-go walks often don’t give a reading, and neither do hills. If your usual walk is short, take the long way once or twice a week."),
            ("Walk briskly", "Fast enough that your heart rate goes up and talking takes a little effort. A slow stroll may not give a reading."),
            ("Let your Watch offer to start it", "On your iPhone: Watch app → Workout → turn on Start Workout Reminder. When your Watch notices you walking, it asks and counts from when you started."),
            ("Keep your Health details up to date", "Your age, height and weight go into the estimate. Health app → your picture → Health Details."),
        ]
        case .heart: [
            ("Wear it to bed", "Most HRV readings are taken overnight. Nights without the Watch leave gaps, so recovery has less to go on."),
            ("Find a charging time that isn’t night", "Charging while you shower or get ready usually keeps it going for a whole day and night."),
            ("Take a 1-minute Breathe session", "Any session in the Mindfulness app records an HRV reading. Sitting still at about the same time each day gives the most comparable numbers."),
            ("Wear it snug, above the wrist bone", "Tight enough not to slide around. Wipe the back if it gets sweaty or has lotion on it."),
        ]
        case .sleep: [
            ("Turn on sleep tracking", "Health app → Browse → Sleep → Full Schedule & Options. Set a schedule and turn on Track Sleep with Apple Watch."),
            ("Get charging reminders", "Watch app → Sleep → Charging Reminders. It nudges you before bed if the battery is too low to last the night."),
            ("Wear it snug overnight", "A loose band can miss wake-ups and get stages wrong."),
        ]
        case .wristTemp: [
            ("Turn on Sleep Focus", "Wrist temperature only records while Sleep Focus is on, so set a sleep schedule and let it turn on by itself."),
            ("Give it about 5 nights", "It needs that long to learn your normal before it shows changes."),
            ("Needs a newer Watch", "Apple Watch Series 8 or later, or any Ultra. Older models don’t have the sensor."),
            ("One warm night isn’t a trend", "A hot room, heavy blankets or drinks can raise it for a night. The app looks at the pattern over several days."),
        ]
        }
    }
}

/// A heads-up that some data is missing or out of date, with the fix.
struct DataNudge: Equatable, Identifiable {
    var id: String
    var metric: TrackedMetric
    var title: String
    var detail: String
}

/// Gaps worth pointing out, most useful first. Only for someone who wears a Watch, so it never
/// nags a phone-only user about Watch data.
func dataNudges(_ h: HealthData, today: String, tracksCycle: Bool) -> [DataNudge] {
    let stagedNights = Set(h.nights.filter { $0.stages?.hasStages == true }.map(\.wakeDate))
    func count(_ days: ClosedRange<Int>, in set: Set<String>) -> Int { days.filter { set.contains(Day.shift(today, -$0)) }.count }
    let wearsWatch = count(1...60, in: stagedNights) > 0 || count(1...60, in: Set(h.hrv.keys)) > 0
    guard wearsWatch else { return [] }
    var out: [DataNudge] = []

    // Skips today: last night may not have synced yet.
    let usuallyWorn = count(8...28, in: stagedNights) >= 7
    let missed = 7 - count(1...7, in: stagedNights)
    if usuallyWorn && missed >= 3 {
        out.append(DataNudge(id: "sleep-gaps", metric: .sleep, title: "No Watch sleep on \(missed) of the last 7 nights",
                             detail: "Recovery and sleep stages need it on overnight. Charging it while you shower or get ready usually keeps it going all night."))
    }

    if let last = h.vo2.last {
        let days = Day.between(last.day, today)
        if days > 30 {
            out.append(DataNudge(id: "vo2-stale", metric: .vo2, title: "Your VO₂ max is \(days / 7) weeks old",
                                 detail: "It only updates during outdoor walks, runs or hikes logged as workouts. Your walk to class counts: start an Outdoor Walk when you leave."))
        }
    } else {
        out.append(DataNudge(id: "vo2-none", metric: .vo2, title: "Get your fitness age",
                             detail: "Start an Outdoor Walk on your Watch next time you walk to class. About 20 brisk minutes on flat ground is usually enough for a VO₂ max reading."))
    }

    if tracksCycle && count(1...14, in: stagedNights) >= 5 && count(1...14, in: Set(h.wristTemp.keys)) == 0 {
        out.append(DataNudge(id: "temp-none", metric: .wristTemp, title: "No wrist temperature yet",
                             detail: "It helps confirm ovulation. It needs Sleep Focus on and an Apple Watch Series 8, Ultra or newer."))
    }
    return out
}

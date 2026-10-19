import Foundation

/// Stress is read from how far your heart rate runs above your resting rate while you're awake
/// and not exercising: about 4 points per bpm above resting, capped at 100.
func stressLevel(heartRate: Double, resting: Double) -> Double {
    max(0, min(100, (heartRate - resting) * 4))
}

struct StressHour: Equatable {
    var hour: Int
    var level: Double
}

struct StressSummary: Equatable {
    var today: [StressHour]
    /// The latest hour's level and how it compares with the same part of past days (0–1).
    var now: Double?
    var percentile: Double?
    var partOfDay: String
    /// Hours today at 60 or above.
    var stressedHours: Int
    /// This week's average vs. the three weeks before (1 = same).
    var weekRatio: Double?

    var label: String {
        guard let now else { return "No data" }
        return now >= 60 ? "Elevated" : now >= 35 ? "Moderate" : "Low"
    }

    var weekLabel: String {
        guard let r = weekRatio else { return "Learning" }
        return r > 1.1 ? "Higher" : r < 0.9 ? "Lower" : "Usual"
    }
}

/// Daily average stress (8am–10pm) by local date.
func dailyStress(_ hourly: [Date: Double], resting: Double) -> [String: Double] {
    var byDay: [String: [Double]] = [:]
    for (start, hr) in hourly {
        let h = Calendar.current.component(.hour, from: start)
        guard (8..<22).contains(h) else { continue }
        byDay[Day.key(start), default: []].append(stressLevel(heartRate: hr, resting: resting))
    }
    return byDay.mapValues { mean($0)! }
}

func stressSummary(_ hourly: [Date: Double], resting: Double?, now: Date = .now) -> StressSummary? {
    guard let resting, !hourly.isEmpty else { return nil }
    let cal = Calendar.current
    let todayStart = cal.startOfDay(for: now)
    let today = hourly.filter { $0.key >= todayStart && cal.component(.hour, from: $0.key) >= 7 }
        .map { StressHour(hour: cal.component(.hour, from: $0.key), level: stressLevel(heartRate: $0.value, resting: resting)) }
        .sorted { $0.hour < $1.hour }
    let latest = today.last
    func part(_ h: Int) -> String { h < 12 ? "mornings" : h < 18 ? "afternoons" : "evenings" }
    var percentile: Double?
    if let latest {
        let same = hourly.filter { $0.key < todayStart && part(cal.component(.hour, from: $0.key)) == part(latest.hour) }
            .map { stressLevel(heartRate: $0.value, resting: resting) }
        if same.count >= 20 { percentile = Double(same.filter { $0 < latest.level }.count) / Double(same.count) }
    }
    let daily = dailyStress(hourly, resting: resting)
    let todayKey = Day.key(now)
    let week = (0..<7).compactMap { daily[Day.shift(todayKey, -$0)] }
    let before = (7..<28).compactMap { daily[Day.shift(todayKey, -$0)] }
    var ratio: Double?
    if week.count >= 3, before.count >= 7, let a = mean(week), let b = mean(before), b > 0 { ratio = a / b }
    return StressSummary(
        today: today, now: latest?.level, percentile: percentile, partOfDay: latest.map { part($0.hour) } ?? "days",
        stressedHours: today.filter { $0.level >= 60 }.count, weekRatio: ratio
    )
}

struct StressFactor: Equatable {
    var name: String
    /// Change vs. your average day, as a fraction (+0.34 = 34% higher).
    var change: Double
}

/// What raises and lowers your stress, from days with and without each thing (needs 3+ days each).
func stressFactors(daily: [String: Double], nights: [Night], exercise: [String: Double], busyDays: Set<String>, lateLutealDays: Set<String>) -> [StressFactor] {
    guard daily.count >= 10, let overall = mean(Array(daily.values)), overall > 0 else { return [] }
    let sleepBefore = Dictionary(nights.map { ($0.wakeDate, $0.asleepMinutes) }, uniquingKeysWith: { a, _ in a })
    let checks: [(String, (String) -> Bool)] = [
        ("Deadline or exam day", { busyDays.contains($0) }),
        ("Under 7h sleep", { (sleepBefore[$0] ?? 999) < 420 }),
        ("Late luteal phase", { lateLutealDays.contains($0) }),
        ("Days with a 20-min walk or workout", { (exercise[$0] ?? 0) >= 20 }),
        ("8+ hours sleep", { (sleepBefore[$0] ?? 0) >= 480 }),
    ]
    return checks.compactMap { name, test in
        let days = daily.filter { test($0.key) }.map(\.value)
        guard days.count >= 3, let m = mean(days) else { return nil }
        return StressFactor(name: name, change: m / overall - 1)
    }
    .filter { abs($0.change) >= 0.05 }
    .sorted { $0.change > $1.change }
}

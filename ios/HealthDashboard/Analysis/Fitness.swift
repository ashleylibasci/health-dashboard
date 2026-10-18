import Foundation

/// Fitness age: the age at which a typical woman has your VO2 max.
/// Typical (50th percentile) VO2 max for women falls from about 38 at 20 to 26 at 60,
/// roughly 44 − 0.3 × age, so fitness age ≈ (44 − VO2 max) / 0.3. An estimate, not a test result.
func fitnessAge(vo2Max: Double) -> Int {
    Int(max(18, min(80, (44 - vo2Max) / 0.3)).rounded())
}

struct FitnessSummary: Equatable {
    var latest: Double
    var fitnessAge: Int
    var peak: Double
    var peakYear: Int
    /// Monthly averages, oldest first, for the trend line.
    var monthly: [(month: String, value: Double)]
    static func == (a: FitnessSummary, b: FitnessSummary) -> Bool { a.latest == b.latest && a.peak == b.peak && a.fitnessAge == b.fitnessAge }
}

func fitnessSummary(_ vo2: [Reading]) -> FitnessSummary? {
    guard let last = vo2.last, let peak = vo2.max(by: { $0.value < $1.value }) else { return nil }
    let byMonth = Dictionary(grouping: vo2) { String($0.day.prefix(7)) }
    let monthly = byMonth.keys.sorted().map { ($0, mean(byMonth[$0]!.map(\.value))!) }
    return FitnessSummary(
        latest: round1(last.value), fitnessAge: fitnessAge(vo2Max: last.value),
        peak: round1(peak.value), peakYear: Calendar.current.component(.year, from: peak.date), monthly: monthly
    )
}

/// A sustained rise in resting heart rate worth mentioning to a doctor: the last month's
/// average at least 8 bpm above the same month six months earlier.
func restingHrRise(_ restingHr: [String: Double], today: String = Day.key(.now)) -> (from: Double, to: Double)? {
    let recent = (0..<30).compactMap { restingHr[Day.shift(today, -$0)] }
    let earlier = (180..<210).compactMap { restingHr[Day.shift(today, -$0)] }
    guard recent.count >= 10, earlier.count >= 10, let to = mean(recent), let from = mean(earlier), to - from >= 8 else { return nil }
    return (from.rounded(), to.rounded())
}

/// Days this week (Sunday on) with at least 20 exercise minutes, the "brisk walk" goal.
func briskDaysThisWeek(_ exercise: [String: Double], today: String = Day.key(.now)) -> Int {
    let start = Day.shift(today, -Day.weekday(today))
    return (0...Day.between(start, today)).filter { (exercise[Day.shift(start, $0)] ?? 0) >= 20 }.count
}

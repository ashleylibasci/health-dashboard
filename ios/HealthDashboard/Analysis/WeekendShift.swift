import Foundation

struct SleepPattern: Equatable {
    var nights: Int
    var bedtime: Double
    var wake: Double
    var asleepMinutes: Double
}

struct WeekendShift: Equatable {
    var schoolNights: SleepPattern
    var weekendNights: SleepPattern
    /// How far the middle of her sleep moves on weekends, in minutes ("social jetlag").
    /// Positive means later on weekends.
    var midpointShift: Int
    var weeks: Int
}

/// Compares school nights (Sun–Thu evenings) with weekend nights (Fri–Sat evenings)
/// over the most recent `weeks` weeks of data.
func weekendShift(_ nights: [Night], weeks: Int = 8) -> WeekendShift? {
    guard let latest = nights.last?.date else { return nil }
    let recent = nights.filter { Day.between($0.date, latest) < weeks * 7 }
    let school = recent.filter { !$0.isWeekend }
    let weekend = recent.filter { $0.isWeekend }
    guard school.count >= 4, weekend.count >= 4 else { return nil }

    func pattern(_ ns: [Night]) -> SleepPattern {
        SleepPattern(
            nights: ns.count,
            bedtime: median(ns.map { Double($0.bedtime) })!,
            wake: median(ns.map { Double($0.wake) })!,
            asleepMinutes: median(ns.map { Double($0.asleepMinutes) })!
        )
    }
    let s = pattern(school), w = pattern(weekend)
    let midpoint = { (p: SleepPattern) in (p.bedtime + p.wake) / 2 }
    return WeekendShift(schoolNights: s, weekendNights: w, midpointShift: Int((midpoint(w) - midpoint(s)).rounded()), weeks: weeks)
}

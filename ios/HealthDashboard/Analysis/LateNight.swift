import Foundation

/// Going to sleep at or after 2am (8 hours after 6pm) counts as a late night.
let lateBedtime = 8 * 60

struct DayEffect: Equatable {
    /// Change in resting heart rate vs. normal, in bpm. Positive = higher (more strain).
    var restingHr: Double?
    /// Change in HRV vs. normal, in ms. Negative = lower (less recovered).
    var hrv: Double?
}

struct LateNightCost: Equatable {
    var lateNights: Int
    var normalNights: Int
    /// Minutes of sleep lost on a late night compared with a normal night.
    var sleepLost: Int
    /// The day she wakes up after the late night.
    var nextDay: DayEffect
    /// The day after that.
    var dayAfter: DayEffect
    var days: Int
}

/// What a late night costs: that night's sleep, and resting HR / HRV on the next two days,
/// each compared with nights she went to bed before 2am.
func lateNightCost(_ nights: [Night], restingHr: [String: Double], hrv: [String: Double], days: Int = 180) -> LateNightCost? {
    guard let latest = nights.last?.date else { return nil }
    let recent = nights.filter { Day.between($0.date, latest) < days }
    let late = recent.filter { $0.bedtime >= lateBedtime }
    // The night after a late night is still recovery, so it isn't a fair "normal".
    let lateDates = Set(late.map(\.date))
    let normal = recent.filter { $0.bedtime < lateBedtime && !lateDates.contains(Day.shift($0.date, -1)) }
    guard late.count >= 3, normal.count >= 3 else { return nil }

    func effect(_ offset: Int) -> DayEffect {
        func diff(_ series: [String: Double]) -> Double? {
            let values = { (ns: [Night]) in ns.compactMap { series[Day.shift($0.wakeDate, offset)] } }
            guard let l = mean(values(late)), let n = mean(values(normal)) else { return nil }
            return round1(l - n)
        }
        return DayEffect(restingHr: diff(restingHr), hrv: diff(hrv))
    }
    let avgSleep = { (ns: [Night]) in mean(ns.map { Double($0.asleepMinutes) })! }
    return LateNightCost(
        lateNights: late.count,
        normalNights: normal.count,
        sleepLost: Int((avgSleep(normal) - avgSleep(late)).rounded()),
        nextDay: effect(0),
        dayAfter: effect(1),
        days: days
    )
}

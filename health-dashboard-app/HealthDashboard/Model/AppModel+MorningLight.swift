import Foundation
import HealthCore

/// The morning daylight target (H-C5): 20 minutes outside before 11am, from
/// the Time in Daylight her Watch already records.
extension AppModel {
    static let morningLightGoal = 20
    /// The hour (on the clock) the morning target ends: 11am.
    static let morningLightEndHour = 11

    /// Minutes in daylight before 11am, from today's hourly Time in Daylight.
    static func morningDaylight(_ hourly: [Int: Double]) -> Int {
        Int(hourly.filter { $0.key < morningLightEndHour }.values.reduce(0, +).rounded())
    }

    /// Shown from waking until midnight (after midnight Health's "today"
    /// is the next calendar day, so the count would read 0).
    var showsMorningLight: Bool { !isAfterMidnight && lastNightIsFresh && now >= lastNight.wake }

    /// "12 of 20 min outside before 11am", "Done: 24 min outside before
    /// 11am", or, after 11am short of it, "12 min before 11am · try tomorrow".
    var morningLightSummary: String {
        let got = morningDaylightToday, goal = Self.morningLightGoal
        if got >= goal { return "Done: \(got)\u{00A0}min outside before 11am" }
        if now < Self.morningLightEndHour * 60 { return "\(got) of \(goal)\u{00A0}min outside before 11am" }
        return "\(got)\u{00A0}min before 11am \u{00B7} try tomorrow"
    }
}

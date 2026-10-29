import Foundation
import HealthCore

/// Sleep regularity in one word (H-C1): "Steady", "Shifting" or "All over
/// the place", from the same 0–100 regularity measure and bands the Sleep
/// history already uses, plus how far her sleep times moved.
extension AppModel {

    struct SleepSteadiness: Hashable {
        enum Level { case steady, shifting, allOver }
        var level: Level
        /// How far her sleep times moved from one night to the next, on
        /// average (falling asleep and waking up together), in minutes.
        var moved: Int

        var word: String {
            switch level {
            case .steady: "Steady"
            case .shifting: "Shifting"
            case .allOver: "All over the place"
            }
        }
        var accent: Accent {
            switch level {
            case .steady: .mint
            case .shifting: .yellow
            case .allOver: .coral
            }
        }
    }

    /// Steadiness over the given nights: steady at a regularity of 75 or
    /// more, shifting from 55, below that all over the place (the bands the
    /// history tile already used). Nil with fewer than 5 nights.
    func steadiness(of nights: [NightRecord]) -> SleepSteadiness? {
        guard let score = regularity(of: nights) else { return nil }
        let ordered = nights.sorted { $0.wakeDay < $1.wakeDay }
        let steps = zip(ordered, ordered.dropFirst()).map { a, b in
            Double(abs(b.sleepOnset - a.sleepOnset) + abs(b.wake - a.wake)) / 2
        }
        let moved = Int((steps.mean ?? 0).rounded())
        let level: SleepSteadiness.Level = score >= 75 ? .steady : score >= 55 ? .shifting : .allOver
        return SleepSteadiness(level: level, moved: moved)
    }

    /// This week's steadiness (the last 7 nights), for the Sleep tab.
    var weekSteadiness: SleepSteadiness? { steadiness(of: sleepHistoryNights(days: 7)) }
}

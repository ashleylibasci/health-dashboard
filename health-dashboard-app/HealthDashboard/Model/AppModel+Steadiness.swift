import Foundation
import HealthCore

/// Sleep regularity in one word (H-C1): "Steady", "Shifting" or "All over
/// the place", from the same 0–100 regularity measure and bands the Sleep
/// history already uses, plus how far her sleep times moved.
extension AppModel {

    struct SleepSteadiness: Hashable {
        enum Level { case steady, shifting, allOver }
        var level: Level
        /// The larger of how far her time falling asleep and her wake time
        /// moved across the nights (latest minus earliest), in minutes.
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
        let onsets = nights.map(\.sleepOnset), wakes = nights.map(\.wake)
        let moved = max((onsets.max() ?? 0) - (onsets.min() ?? 0), (wakes.max() ?? 0) - (wakes.min() ?? 0))
        let level: SleepSteadiness.Level = score >= 75 ? .steady : score >= 55 ? .shifting : .allOver
        return SleepSteadiness(level: level, moved: moved)
    }

    /// This week's steadiness (the last 7 nights), for the Sleep tab.
    var weekSteadiness: SleepSteadiness? { steadiness(of: sleepHistoryNights(days: 7)) }
}

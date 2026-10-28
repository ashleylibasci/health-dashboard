import Foundation
import HealthCore

/// Does the score match how she felt? (H-E3) Recovery and energy each put
/// a day in one of three bands (above usual, about usual, below), and so
/// does her morning check-in (4–5 awake, 3, 1–2). A day matches when both
/// land in the same band.
extension AppModel {
    struct ScoreMatch: Hashable {
        var matched: Int
        var days: Int
    }

    /// Days with a check-in needed before the match is shown.
    static let scoreMatchMinimumDays = 7
    /// How far back it looks.
    static let scoreMatchDays = 30

    private enum Band { case low, middle, high }

    private static func feltBand(_ checkIn: Double) -> Band {
        let awake = checkIn.rounded()
        return awake >= 4 ? .high : awake >= 3 ? .middle : .low
    }

    /// Nights in the last 30 days, before today's, with a morning check-in.
    private var checkedInNights: [NightRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.scoreMatchDays, to: appDayDate) ?? .distantPast
        return nights.filter { $0.wakeDay > cutoff && $0.wakeDay < lastNightWakeDay && $0.outcome.checkIn != nil }
    }

    /// Recovery against her check-in: "Ready to push" is above usual, "On
    /// track" about usual, "Take it steady" and "Go easy" below.
    var recoveryMatch: ScoreMatch {
        let need = sleepNeed.minutes
        let days = checkedInNights.filter { $0.outcome.hrvDeltaPct != nil || $0.outcome.restingHRDelta != nil }
        let matched = days.filter { n in
            let score = Recovery.score(usual: Double(Self.recoveryAnchor), hrvDeltaPct: n.outcome.hrvDeltaPct ?? 0,
                                       restingHRDelta: n.outcome.restingHRDelta ?? 0,
                                       sleepShortfall: max(0, need - n.asleepMinutes - SleepNeedEstimator.metNeedToleranceMinutes),
                                       cycle: cycleHeartShift(on: n.wakeDay))
            let band: Band = switch recoveryLevel(for: score) {
            case .push: .high
            case .onTrack: .middle
            case .steady, .easy: .low
            }
            return band == Self.feltBand(n.outcome.checkIn ?? 3)
        }
        return ScoreMatch(matched: matched.count, days: days.count)
    }

    /// The day's energy score against her check-in: 5 or more points above
    /// her usual is above, 5 or more below is below (recovery's narrowest band).
    var energyMatch: ScoreMatch {
        let k = Int(Recovery.band(spread: nil))
        let days = checkedInNights
        let matched = days.filter { n in
            let d = energyScore(for: n) - energyUsual
            let band: Band = d >= k ? .high : d > -k ? .middle : .low
            return band == Self.feltBand(n.outcome.checkIn ?? 3)
        }
        return ScoreMatch(matched: matched.count, days: days.count)
    }

    /// "Matched your morning check-in on 18 of 25 days", or how many more
    /// check-ins it needs.
    func scoreMatchSummary(_ m: ScoreMatch) -> String {
        guard m.days >= Self.scoreMatchMinimumDays else {
            return "Needs \(Self.scoreMatchMinimumDays) mornings with a check-in (\(m.days) so far)"
        }
        return "Matched your morning check-in on \(m.matched) of \(m.days) days"
    }

    /// What a match means, for the row's open state.
    func scoreMatchDetail(_ score: String) -> String {
        "Each morning you check in, we put your \(score) and how awake you felt into one of three groups: better than usual, about usual or worse. A day matches when both land in the same group. It\u{2019}s a way to see whether the number works for you; it never changes the number. From the last \(Self.scoreMatchDays) days."
    }
}

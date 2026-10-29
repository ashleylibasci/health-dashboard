import Foundation
import HealthCore

/// Does the score match how she felt? (H-E3) Recovery and energy each put
/// a day in one of three bands (above usual, about usual, below), and so
/// does her morning check-in against her own average check-in (half a
/// point or more either way). A day matches when both land in the same band.
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

    /// How far from her average check-in (1–5) counts as feeling better
    /// or worse than usual.
    static let feltMargin = 0.5

    private static func feltBand(_ checkIn: Double, usual: Double) -> Band {
        let d = checkIn - usual
        return d >= feltMargin ? .high : d > -feltMargin ? .middle : .low
    }

    /// Her average check-in over the nights being matched.
    private static func usualCheckIn(_ nights: [NightRecord]) -> Double {
        nights.compactMap(\.outcome.checkIn).mean ?? 3
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
        let usual = Self.usualCheckIn(days)
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
            return band == Self.feltBand(n.outcome.checkIn ?? usual, usual: usual)
        }
        return ScoreMatch(matched: matched.count, days: days.count)
    }

    /// The day's energy score against her check-in: 5 or more points above
    /// her usual is above, 5 or more below is below (recovery's narrowest
    /// band). Scoring 30 past days is slow, so it's kept until the nights,
    /// her need setting or her usual change.
    var energyMatch: ScoreMatch {
        var h = Hasher()
        h.combine(nights)
        h.combine(store.data.sleepNeedAdjustment)
        h.combine(energyUsual)
        h.combine(appDayDate)
        let key = h.finalize()
        if let cached = ScoreMatchCache.shared.energy, cached.key == key { return cached.match }
        let match = computeEnergyMatch()
        ScoreMatchCache.shared.energy = (key, match)
        return match
    }

    private func computeEnergyMatch() -> ScoreMatch {
        let k = Int(Recovery.band(spread: nil))
        let days = checkedInNights
        let usual = Self.usualCheckIn(days)
        let matched = days.filter { n in
            let d = energyScore(for: n) - energyUsual
            let band: Band = d >= k ? .high : d > -k ? .middle : .low
            return band == Self.feltBand(n.outcome.checkIn ?? usual, usual: usual)
        }
        return ScoreMatch(matched: matched.count, days: days.count)
    }

    /// "Matched your check-in 18 of 25 days", or how many more
    /// check-ins it needs.
    func scoreMatchSummary(_ m: ScoreMatch) -> String {
        guard m.days >= Self.scoreMatchMinimumDays else {
            return "Needs \(Self.scoreMatchMinimumDays) check-ins (\(m.days) so far)"
        }
        return "Matched your check-in \(m.matched) of \(m.days) days"
    }

    /// What a match means, for the row's open state.
    func scoreMatchDetail(_ score: String) -> String {
        "Each morning you check in, we put your \(score) and how awake you felt (compared with your average check-in) into one of three groups: better than usual, about usual or worse. A day matches when both land in the same group. It\u{2019}s a way to see whether the number works for you; it never changes the number. From the last \(Self.scoreMatchDays) days."
    }
}

/// The last energy match, with the inputs it was worked out from.
@MainActor
private final class ScoreMatchCache {
    static let shared = ScoreMatchCache()
    var energy: (key: Int, match: AppModel.ScoreMatch)?
}

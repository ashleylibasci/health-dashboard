import Foundation
import HealthCore

/// Derived values for the Today, Sleep, wake-plan and recovery screens.
/// Display helpers only; the models themselves live in HealthCore.
extension AppModel {

    // MARK: Regularity

    /// 0–100: how steady sleep timing was over the last 14 nights. A simple
    /// stand-in for a full Sleep Regularity Index: it falls as the spread
    /// (standard deviation) of sleep onset and wake times grows. A spread of
    /// about 55 minutes scores about 75. Nil with fewer than 5 nights.
    var sleepRegularityScore: Int? {
        let recent = Array(nights.sorted { $0.wakeDay > $1.wakeDay }.prefix(14))
        guard recent.count >= 5 else { return nil }
        let onsetSD = recent.map { Double($0.sleepOnset) }.standardDeviation ?? 0
        let wakeSD = recent.map { Double($0.wake) }.standardDeviation ?? 0
        let spread = (onsetSD + wakeSD) / 2
        return Int(min(max(100 - spread * 0.45, 0), 100).rounded())
    }

    // MARK: Recovery history

    /// Recovery for one past night, scored with the same HealthCore model
    /// as today's number.
    struct RecoveryNight: Identifiable, Hashable {
        var id: Date { day }
        var day: Date
        var score: Int
        var bedtime: Minutes
        var asleep: Int
    }

    /// Recovery for the last `days` nights that have HRV or resting heart
    /// rate, oldest first.
    func recoveryHistory(days: Int = 14) -> [RecoveryNight] {
        let need = sleepNeed.minutes
        let recent = nights
            .filter { $0.outcome.hrvDeltaPct != nil || $0.outcome.restingHRDelta != nil }
            .sorted { $0.wakeDay < $1.wakeDay }
            .suffix(days)
        return recent.map { n in
            let score = Recovery.score(usual: Double(AppModel.recoveryAnchor),
                                       hrvDeltaPct: n.outcome.hrvDeltaPct ?? 0,
                                       restingHRDelta: n.outcome.restingHRDelta ?? 0,
                                       sleepShortfall: max(0, need - n.asleepMinutes - SleepNeedEstimator.metNeedToleranceMinutes),
                                       cycle: cycleHeartShift(on: n.wakeDay))
            return RecoveryNight(day: n.wakeDay, score: score, bedtime: n.bedtime, asleep: n.asleepMinutes)
        }
    }

    /// How many points each input moved today's recovery, measured by
    /// scoring each input alone against the usual (HealthCore's model).
    /// HRV and resting heart rate with a natural cycle's own shift taken
    /// out, as in the score.
    var recoveryPointsFromHRV: Int {
        Recovery.score(usual: Double(AppModel.recoveryAnchor), hrvDeltaPct: cycleHeartShift.adjust(hrvDeltaPct: hrvDeltaPct),
                       restingHRDelta: 0, sleepShortfall: 0) - AppModel.recoveryAnchor
    }
    var recoveryPointsFromRestingHR: Int {
        Recovery.score(usual: Double(AppModel.recoveryAnchor), hrvDeltaPct: 0,
                       restingHRDelta: cycleHeartShift.adjust(restingHRDelta: restingHRDelta), sleepShortfall: 0) - AppModel.recoveryAnchor
    }
    var recoveryPointsFromSleep: Int {
        let shortfall = max(0, sleepNeed.minutes - lastNight.asleep - SleepNeedEstimator.metNeedToleranceMinutes)
        return Recovery.score(usual: Double(AppModel.recoveryAnchor), hrvDeltaPct: 0, restingHRDelta: 0, sleepShortfall: shortfall) - AppModel.recoveryAnchor
    }

    // MARK: Nights

    /// Average sleep on nights with an alarm ("school nights").
    var alarmNightAverageAsleep: Int? {
        let xs = nights.filter(\.alarmUsed).map { Double($0.asleepMinutes) }
        return xs.mean.map { Int($0.rounded()) }
    }

    /// Light-sleep wake-ups over the most recent `count` nights that recorded
    /// a wake stage.
    func lightSleepWakeCount(lastNights count: Int) -> (light: Int, total: Int) {
        let known = nights.sorted { $0.wakeDay > $1.wakeDay }
            .compactMap { $0.wokeFromLightSleep }
            .prefix(count)
        return (known.filter { $0 }.count, known.count)
    }
}

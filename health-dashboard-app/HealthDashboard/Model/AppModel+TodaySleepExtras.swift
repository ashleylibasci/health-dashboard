import Foundation
import HealthCore

/// Extra derived values for the Today, Sleep, stress, history and accuracy
/// screens. Computed only; nothing here is stored.
extension AppModel {

    // MARK: Last night's stage timeline

    /// Last night's stages in order. Real Apple Health segments when there
    /// are any. With sample data, a typical night (deep sleep early, REM
    /// late) shaped to match last night's stage totals, so the timeline can
    /// be shown and explored. Empty for a real night without stage data.
    var lastNightTimeline: [StageSegment] {
        if !lastNight.segments.isEmpty { return lastNight.segments }
        guard usingSampleData else { return [] }
        return Self.typicalNight(onset: lastNight.onset, wake: lastNight.wake,
                                 stageMinutes: lastNight.stageMinutes, wakeDay: appDayDate)
    }

    static func typicalNight(onset: Minutes, wake: Minutes, stageMinutes: [SleepStage: Int], wakeDay: Date) -> [StageSegment] {
        // Five cycles: deep sleep front-loaded, REM growing toward morning.
        let template: [(SleepStage, Double)] = [
            (.core, 12), (.deep, 30), (.core, 14), (.rem, 8),
            (.core, 22), (.deep, 22), (.core, 12), (.rem, 14),
            (.core, 26), (.deep, 12), (.awake, 4), (.core, 14), (.rem, 20),
            (.core, 30), (.deep, 6), (.rem, 26), (.awake, 6),
            (.core, 32), (.rem, 34), (.awake, 4), (.core, 12),
        ]
        var templateTotals: [SleepStage: Double] = [:]
        for (stage, m) in template { templateTotals[stage, default: 0] += m }
        let scaled: [(SleepStage, Double)] = template.map { stage, m in
            let target = Double(stageMinutes[stage] ?? 0)
            let total = templateTotals[stage] ?? 1
            return (stage, total > 0 ? m * target / total : 0)
        }
        let sum = scaled.map(\.1).reduce(0, +)
        let span = Double(max(wake - onset, 1))
        guard sum > 0 else { return [] }
        let start = Clock.date(onset, relativeTo: wakeDay)
        var t = 0.0
        var out: [StageSegment] = []
        for (stage, m) in scaled where m > 0 {
            let length = m / sum * span
            let a = start.addingTimeInterval(t * 60)
            let b = start.addingTimeInterval((t + length) * 60)
            out.append(StageSegment(stage: stage, start: a, end: b))
            t += length
        }
        return out
    }

    // MARK: Sleep history

    /// Nights from the last `days` days, oldest first.
    func sleepHistoryNights(days: Int) -> [NightRecord] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now)) ?? .distantPast
        return nights.filter { $0.wakeDay > cutoff }.sorted { $0.wakeDay < $1.wakeDay }
    }

    /// 0–100 steadiness of sleep and wake times for the given nights, the
    /// same measure as `sleepRegularityScore`. Nil with fewer than 5 nights.
    func regularity(of nights: [NightRecord]) -> Int? {
        guard nights.count >= 5 else { return nil }
        let onsetSD = nights.map { Double($0.sleepOnset) }.standardDeviation ?? 0
        let wakeSD = nights.map { Double($0.wake) }.standardDeviation ?? 0
        let spread = (onsetSD + wakeSD) / 2
        return Int(min(max(100 - spread * 0.45, 0), 100).rounded())
    }

    // MARK: HRV and resting heart rate history

    struct HeartNight: Identifiable, Hashable {
        var id: Date { day }
        var day: Date
        var hrv: Double?
        var restingHR: Double?
    }

    /// Morning HRV (ms) and resting heart rate (bpm) for recent nights,
    /// rebuilt from each night's change against the usual. Oldest first.
    func heartTrend(days: Int = 14) -> [HeartNight] {
        let hrvBase = usingSampleData ? SampleData.baselineHRV : baselineHRV
        let rhrBase = baselineRestingHR
        return sleepHistoryNights(days: days).compactMap { n in
            let h = n.outcome.hrvDeltaPct.map { hrvBase * (1 + $0 / 100) }
            let r = n.outcome.restingHRDelta.map { rhrBase + $0 }
            guard h != nil || r != nil else { return nil }
            return HeartNight(day: n.wakeDay, hrv: h, restingHR: r)
        }
    }

    // MARK: Check-ins and logs

    /// Morning check-ins in the last `days` days, oldest first.
    func checkIns(lastDays days: Int) -> [AppData.CheckIn] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now)) ?? .distantPast
        return store.data.checkIns.filter { $0.date > cutoff }.sorted { $0.date < $1.date }
    }

    /// How many of the last `days` days have at least one entry.
    func daysWithEntries(_ dates: [Date], lastDays days: Int) -> Int {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now)) ?? .distantPast
        return Set(dates.filter { $0 > cutoff }.map { cal.startOfDay(for: $0) }).count
    }

    /// Hours today with a heart rate reading (the Watch was worn).
    var watchWornHoursToday: Int { stressSamples.filter { $0.heartRate != nil }.count }

    /// Whether a night ending this morning was recorded.
    var nightRecordedThisMorning: Bool { lastNightIsFresh && lastNightIsReal }

    struct MoodDay: Hashable {
        var day: Date
        var stress: Int?
    }

    /// Mood log entries (how stressed she felt) from the last 7 days, by day.
    var moodWeek: [MoodDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().map { back in
            let day = cal.date(byAdding: .day, value: -back, to: today) ?? today
            let entry = store.data.moodLog.filter { cal.isDate($0.date, inSameDayAs: day) }.last
            return MoodDay(day: day, stress: entry?.stress)
        }
    }
}

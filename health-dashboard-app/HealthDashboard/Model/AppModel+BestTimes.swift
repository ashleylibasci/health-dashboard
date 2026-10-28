import Foundation
import HealthCore

/// Her best bedtime and wake time (HealthCore `SleepTiming`, Park's method),
/// and the one bedtime the whole app uses tonight. Today's Tonight card, the
/// Sleep tab, the wake plan, the smart alarm, the Watch and the widgets all
/// read `tonightBedtime`, so there is never a second, competing time.
extension AppModel {

    /// Tonight's bedtime: "bed by" from her best times, or earlier when
    /// tonight's need (debt payback, a hard day, fighting something off) is
    /// more than her base need. Rounded down to 5 minutes, like the rest.
    var tonightBedtime: Minutes {
        let best = bestTimes
        let up = store.data.upBy
        let shift = clockShiftTonight(bedtime: best.bed.end, deadline: up)
        let forTonight = Int((Double(up - shift - tonightNeed.total - best.latency) / 5).rounded(.down)) * 5
        return min(best.bed.end, forTonight)
    }

    /// Minutes tonight's bedtime is earlier than her usual best (0 most nights).
    var tonightEarlierThanBest: Int { max(bestTimes.bed.end - tonightBedtime, 0) }

    /// Her best bedtime window and wake window. Her own nights count only
    /// once they're real (never example nights); before then it's the
    /// window from her need and body clock, labelled like everything else.
    var bestTimes: SleepTiming.Result {
        let key = bestTimesKey
        if let cached = BestTimesCache.shared.result(for: key) { return cached }
        let result = SleepTiming.recommend(bestTimesInput)
        BestTimesCache.shared.store(result, for: key)
        return result
    }

    /// Everything the best times read, hashed: nights, the logs behind the
    /// flags, cycle and pack settings, up-by and the date.
    private var bestTimesKey: Int {
        var h = Hasher()
        h.combine(nights)
        h.combine(realNightDays)
        h.combine(usingSampleData)
        h.combine(store.data.upBy)
        h.combine(store.data.sleepNeedAdjustment)
        h.combine(store.data.alcoholLog)
        h.combine(store.data.exams)
        h.combine(store.data.symptomLog)
        h.combine(store.data.flowLog)
        h.combine(store.data.drinkLog.count)
        h.combine(store.data.drinkLog.last?.date)
        h.combine(store.data.packStartDate)
        h.combine(store.data.packLength)
        h.combine(store.data.packActiveDays)
        h.combine(store.data.cycleSetup)
        h.combine(store.data.birthControl)
        h.combine(healthPeriodStarts)
        h.combine(workNights.count)
        h.combine(freeNights.count)
        h.combine(sessions.count)
        h.combine(nextWakeDay)
        return h.finalize()
    }

    /// The usual bedtime she set (Settings, Sleep plan) is within 15 minutes
    /// of "bed by". Tonight's numbers (caffeine cutoff, energy curve) use
    /// `tonightBedtime` either way; exam plans and streaks use the usual one.
    var bedtimeMatchesBest: Bool { abs(store.data.bedtime - bestTimes.bed.end) <= 15 }

    /// Her own sleep onset against next-morning HRV, in 30-minute slots
    /// (the nights the method compares).
    var bestTimesSlots: [SleepTiming.Slot] { SleepTiming.slots(bestTimesInput.nights) }

    private var bestTimesInput: SleepTiming.Input {
        let up = store.data.upBy
        let need = sleepNeed.minutes
        let probe = up - need - Self.planLatency
        return SleepTiming.Input(nights: timingNights, need: need, upBy: up, latency: Self.planLatency,
                                 cycleLength: sleepCycleLength, chronotype: chronotype,
                                 freeNights: freeNights.count, workNights: workNights.count,
                                 clockShift: clockShiftTonight(bedtime: probe, deadline: up),
                                 windowLength: Self.alarmWindowLead)
    }

    /// Her real nights with what the app knows about each: drinks, exams,
    /// symptoms, a clock change, her cycle or pill week, late caffeine.
    private var timingNights: [SleepTiming.Night] {
        let cal = Calendar.current
        let real = nights.filter(isRealNight).sorted { $0.wakeDay < $1.wakeDay }.suffix(SleepTiming.historyNights)
        guard !real.isEmpty else { return [] }
        let examDays = store.data.exams.map { cal.startOfDay(for: $0.date) }
        let unwellDays = Set(store.data.symptomLog.filter { !$0.symptoms.isEmpty }.map { cal.startOfDay(for: $0.date) })
        // Caffeine after 2pm belongs to the night that follows it.
        let lateCaffeineNights = Set(store.data.drinkLog.compactMap { d -> Date? in
            let day = AppDay.day(containing: d.date)
            guard AppDay.minutes(d.date, relativeTo: day) >= 14 * 60 else { return nil }
            return cal.date(byAdding: .day, value: 1, to: day)
        })
        return real.map { n in
            let day = cal.startOfDay(for: n.wakeDay)
            var flags: SleepTiming.Flags = []
            let drinks = NightPairing.alcoholWindow(wakeDay: day)
            if store.data.alcoholLog.contains(where: { drinks.contains($0.date) }) { flags.insert(.alcohol) }
            if examDays.contains(where: { exam in
                (0...2).contains(cal.dateComponents([.day], from: day, to: exam).day ?? -1)
            }) { flags.insert(.exam) }
            if unwellDays.contains(day) { flags.insert(.unwell) }
            let elapsed = Int((Clock.date(n.wake, relativeTo: day).timeIntervalSince(Clock.date(n.bedtime, relativeTo: day)) / 60).rounded())
            if elapsed != n.wake - n.bedtime { flags.insert(.clockChange) }
            let shift = cycleHeartShift(on: day)
            if shift == .luteal { flags.insert(.luteal) }
            if isPillBreakWeek(on: day) { flags.insert(.breakWeek) }
            if lateCaffeineNights.contains(day) { flags.insert(.lateCaffeine) }
            let week = Int((day.timeIntervalSinceReferenceDate / (7 * 86_400)).rounded(.down))
            return SleepTiming.Night(record: n, flags: flags, cycleShift: shift, wakeWeek: week)
        }
    }

    /// A pill break-week day, from the pack start she set (nil without one).
    private func isPillBreakWeek(on day: Date) -> Bool {
        guard let start = store.data.packStartDate, store.birthControl != nil else { return false }
        let length = max(store.data.packLength, 1)
        let active = min(max(store.data.packActiveDays, 1), length)
        guard active < length else { return false }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: day).day ?? 0
        return ((days % length) + length) % length + 1 > active
    }
}

/// The last best-times result and the key of what it read. Screens ask
/// for tonight's bedtime many times per redraw; the method only reruns
/// when a night, a log or a setting it reads has changed.
@MainActor
private final class BestTimesCache {
    static let shared = BestTimesCache()
    private var last: (key: Int, result: SleepTiming.Result)?

    func result(for key: Int) -> SleepTiming.Result? {
        guard let last, last.key == key else { return nil }
        return last.result
    }

    func store(_ result: SleepTiming.Result, for key: Int) { last = (key, result) }
}

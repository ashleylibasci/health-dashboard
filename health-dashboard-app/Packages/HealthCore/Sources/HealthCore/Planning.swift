import Foundation

// MARK: - Clock change

/// A night-by-night plan around a daylight-saving change.
public enum TimeChangePlanner {
    public enum Strategy: String, Sendable, CaseIterable {
        /// Fall back: keep the body clock, so the clock reads an hour earlier.
        case useItToWakeEarlier
        /// Keep your usual bedtime and wake time by the clock. Nothing moves.
        case keepClockTimes
    }
    public struct Night: Hashable, Sendable {
        public var dayOffset: Int        // 0 = the night the clocks change
        public var bedtime: Minutes      // on the clock in use that night
        public var wake: Minutes         // on the clock in use the next morning
        public var note: String?
    }

    /// `shiftMinutes` is -60 when clocks fall back, +60 when they spring forward.
    public static func plan(bedtime: Minutes, wake: Minutes, shiftMinutes: Int, strategy: Strategy, nightsBefore: Int = 3, nightsAfter: Int = 2) -> [Night] {
        (-nightsBefore...nightsAfter).map { i in
            switch strategy {
            case .useItToWakeEarlier:
                if i < 0 { return Night(dayOffset: i, bedtime: bedtime, wake: wake, note: nil) }
                if i == 0 { return Night(dayOffset: 0, bedtime: bedtime, wake: wake + shiftMinutes, note: "Feels like \(Clock.format(wake))") }
                return Night(dayOffset: i, bedtime: bedtime + shiftMinutes, wake: wake + shiftMinutes, note: nil)
            case .keepClockTimes:
                // Same bedtime and wake by the clock every night. Falling back
                // just adds an hour of sleep the night it happens.
                if i == 0 {
                    let note = shiftMinutes < 0 ? "Clocks go back tonight: you get an extra hour" : "Clocks go forward tonight: you lose an hour"
                    return Night(dayOffset: 0, bedtime: bedtime, wake: wake, note: note)
                }
                return Night(dayOffset: i, bedtime: bedtime, wake: wake, note: nil)
            }
        }
    }
}

// MARK: - Recovery

/// Readiness from HRV and resting heart rate against her own baseline, plus
/// sleep against need.
public enum Recovery {
    public static func score(usual: Double = 78, hrvDeltaPct: Double, restingHRDelta: Double, sleepShortfall: Int) -> Int {
        let s = usual + hrvDeltaPct * 1.0 - restingHRDelta * 1.5 - Double(max(sleepShortfall, 0)) * 0.06
        return Int(min(max(s, 1), 100).rounded())
    }
    /// `spread` is how much her own score usually moves day to day (the
    /// standard deviation of her recent scores, once there are 14 days). The
    /// bands scale with it, so someone whose score swings ±10 isn't told
    /// "Ready to push" or "Take it steady" for an ordinary day. Without it
    /// the bands are ±5 and −15.
    public static func label(_ score: Int, usual: Int, spread: Double? = nil) -> String {
        let k = band(spread: spread)
        let d = Double(score - usual)
        if d >= k { return "Ready to push" }
        if d > -k { return "On track" }
        if d > -3 * k { return "Take it steady" }
        return "Go easy today"
    }

    /// Half her day-to-day spread, kept between 5 and 12 points.
    public static func band(spread: Double?) -> Double {
        guard let s = spread, s > 0 else { return 5 }
        return min(max(s * 0.5, 5), 12)
    }
}

// MARK: - Menstrual cycle phase

public enum CyclePhase: String, Sendable { case period, follicular, ovulation, luteal, unknown }

public enum CycleEstimator {
    /// Phase on `day` (1 = first day of the period) for a cycle of `length`.
    public static func phase(day: Int, length: Int = 29, periodLength: Int = 5) -> CyclePhase {
        guard day >= 1 else { return .unknown }
        let ovulation = length - 14
        switch day {
        case 1...periodLength: return .period
        case ..<(ovulation - 1): return .follicular
        case (ovulation - 1)...(ovulation + 1): return .ovulation
        default: return .luteal
        }
    }
    public static func isLateLuteal(day: Int, length: Int = 29) -> Bool { phase(day: day, length: length) == .luteal && day >= length - 9 }

    /// Usual cycle length (median of the gaps between period starts that
    /// fall in 20–45 days). Nil when there are no such gaps: callers must not
    /// make one up. See `lengths` for cycles that run longer.
    public static func averageLength(periodStarts: [Date], calendar: Calendar = .current) -> Int? {
        lengths(periodStarts: periodStarts, calendar: calendar).usual
    }

    public struct Lengths: Hashable, Sendable {
        /// Every gap between consecutive starts, oldest first.
        public var gaps: [Int]
        /// Median of the 20–45 day gaps; nil when there are none.
        public var usual: Int?
        /// Most of her cycles (more than half, or all of one) ran longer than
        /// 45 days: no usual length can be given, and an "overdue" countdown
        /// against a typical 29 days would be wrong every cycle.
        public var runLong: Bool
    }

    public static func lengths(periodStarts: [Date], calendar: Calendar = .current) -> Lengths {
        let s = periodStarts.sorted()
        guard s.count >= 2 else { return Lengths(gaps: [], usual: nil, runLong: false) }
        let gaps = zip(s, s.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day ?? 0 }
        let normal = gaps.filter { (20...45).contains($0) }.map(Double.init)
        let long = gaps.filter { $0 > 45 }.count
        return Lengths(gaps: gaps, usual: normal.median.map { Int($0.rounded()) }, runLong: long * 2 > gaps.count)
    }
}

// MARK: - Weekly recap

public struct DaySummary: Hashable, Sendable {
    public var date: Date
    public var energy: Int
    public var asleep: Int
    public var bedtime: Minutes
    public var wake: Minutes
    public var wokeFromLightSleep: Bool
    public var daylightMinutes: Int
    public var caffeineMg: Int
    public var lastCaffeine: Minutes?
    /// Her morning check-in that day (1–5), if she did one: the only measure
    /// of the day that caffeine and daylight could show up in.
    public var checkIn: Double?
    public init(date: Date, energy: Int, asleep: Int, bedtime: Minutes, wake: Minutes, wokeFromLightSleep: Bool, daylightMinutes: Int, caffeineMg: Int, lastCaffeine: Minutes?, checkIn: Double? = nil) {
        self.date = date; self.energy = energy; self.asleep = asleep; self.bedtime = bedtime; self.wake = wake
        self.wokeFromLightSleep = wokeFromLightSleep; self.daylightMinutes = daylightMinutes; self.caffeineMg = caffeineMg; self.lastCaffeine = lastCaffeine
        self.checkIn = checkIn
    }
}

public struct WeekRecap: Hashable, Sendable {
    public var averageEnergy: Int
    public var best: DaySummary
    public var worst: DaySummary
    public var averageAsleep: Int
    public var lightSleepWakes: Int
    public var averageDaylight: Int
    public var averageCaffeine: Int
    /// Habits shared by the better half of the week but not the worse half.
    public var bestDayHabits: [String]
    public var worstDayIssues: [String]
    /// True when the better and worse halves were picked by her own morning
    /// check-ins (3+ days had one). Otherwise they were picked by the
    /// modelled energy score, which only knows about sleep, so only sleep
    /// habits are tested (caffeine and daylight would be circular).
    public var habitsFromCheckIns: Bool = false

    /// `lateThreshold`: her late-bedtime threshold (the app-wide one); without
    /// it, 90 minutes past this week's median.
    public static func make(days: [DaySummary], need: Int, bestWindow: TimeRange?, lateThreshold: Minutes? = nil) -> WeekRecap? {
        guard days.count >= 3 else { return nil }
        let sorted = days.sorted { $0.energy > $1.energy }
        func share(_ xs: [DaySummary], _ f: (DaySummary) -> Bool) -> Double { Double(xs.filter(f).count) / Double(xs.count) }

        // Better vs worse days: by how she said she felt when she can tell us.
        let rated = days.filter { $0.checkIn != nil }
        let byCheckIn = rated.count >= 3
        let ranked = byCheckIn ? rated.sorted { ($0.checkIn ?? 0) > ($1.checkIn ?? 0) } : sorted
        let top = Array(ranked.prefix(ranked.count / 2)), bottom = Array(ranked.suffix(ranked.count / 2))

        var habits: [String] = []
        typealias Check = (label: String, test: (DaySummary) -> Bool)
        var checks: [Check] = []
        checks.append(("Slept at least \(Clock.duration(need)), your need", { (d: DaySummary) -> Bool in SleepNeedEstimator.metNeed(asleep: d.asleep, need: need) }))
        checks.append(("Woke at the end of a sleep cycle", { (d: DaySummary) -> Bool in d.wokeFromLightSleep }))
        if byCheckIn {
            checks.append(("20+ minutes of daylight", { (d: DaySummary) -> Bool in d.daylightMinutes >= 20 }))
            checks.append(("Last caffeine before noon", { (d: DaySummary) -> Bool in (d.lastCaffeine ?? 0) < 720 }))
        }
        if let w = bestWindow { checks.append(("Woke \(w.label)", { (d: DaySummary) -> Bool in w.contains(d.wake) })) }
        if !top.isEmpty && !bottom.isEmpty {
            for (label, test) in checks where share(top, test) - share(bottom, test) >= 0.5 { habits.append(label) }
        }

        let w = sorted.last!
        var issues: [String] = []
        // Late compared with her own usual bedtime, not a fixed 2am.
        if w.bedtime >= (lateThreshold ?? LateNights.threshold(bedtimes: days.map(\.bedtime))) { issues.append("Bed at \(Clock.format(w.bedtime))") }
        if !w.wokeFromLightSleep { issues.append("Woke mid-cycle, from deep sleep") }
        if !SleepNeedEstimator.metNeed(asleep: w.asleep, need: need) { issues.append("\(Clock.duration(need - w.asleep)) short of your need") }
        if (w.lastCaffeine ?? 0) > 840 { issues.append("Caffeine after 2pm") }

        func avg(_ xs: [Int]) -> Int { Int((Double(xs.reduce(0, +)) / Double(xs.count)).rounded()) }
        return WeekRecap(averageEnergy: avg(days.map(\.energy)), best: sorted.first!, worst: w,
                         averageAsleep: avg(days.map(\.asleep)), lightSleepWakes: days.filter(\.wokeFromLightSleep).count,
                         averageDaylight: avg(days.map(\.daylightMinutes)), averageCaffeine: avg(days.map(\.caffeineMg)),
                         bestDayHabits: habits, worstDayIssues: issues, habitsFromCheckIns: byCheckIn)
    }
}

// MARK: - Exam planning

public struct ExamDayPlan: Hashable, Sendable {
    public var dayOffset: Int        // 0 = exam day
    public var bedtimeBefore: Minutes
    public var wake: Minutes
    public var alarmWindow: TimeRange
    public var studyBlocks: [TimeRange]
    public var caffeineBy: Minutes
}

public enum ExamPlanner {
    /// Plans the nights before an exam. Exam morning wakes at least
    /// `clearHeadMinutes` before the start so grogginess has passed.
    /// `caffeineCutoff`: her own cutoff for the study days (it's earlier on
    /// the combined pill, ring or patch); 2pm when not given.
    public static func plan(examStart: Minutes, daysUntil: Int, usualBedtime: Minutes, latency: Int = 12, cycleLength: Int = 92, need: Int, energyTemplate: EnergyDay, clearHeadMinutes: Int = 70, caffeineCutoff: Minutes? = nil) -> [ExamDayPlan] {
        var days: [ExamDayPlan] = []
        for offset in stride(from: -daysUntil, through: 0, by: 1) {
            let isExam = offset == 0
            let deadline = isExam ? examStart - clearHeadMinutes : usualBedtime + latency + need + 30
            // Latest bedtime with five whole cycles before the deadline.
            let cycles = max(4, Int((Double(need) / Double(cycleLength)).rounded(.down)))
            let bed = min(usualBedtime, deadline - cycles * cycleLength - latency)
            let wake = bed + latency + cycles * cycleLength
            let blocks = isExam ? [] : [energyTemplate.zone(.morningPeak)?.range, energyTemplate.zone(.secondWind)?.range].compactMap { $0 }
            days.append(ExamDayPlan(dayOffset: offset, bedtimeBefore: bed, wake: wake,
                                    alarmWindow: TimeRange(wake - 30, wake + 3), studyBlocks: blocks,
                                    caffeineBy: isExam ? examStart - 45 : (caffeineCutoff ?? 840)))
        }
        return days
    }
}

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
    /// `cycle`: the shift a natural cycle puts on HRV and resting heart rate
    /// today (`CycleHeartShift`). It's taken out before scoring, so the
    /// second half of her cycle doesn't read as poor recovery and her period
    /// week doesn't read as extra good. `.none` on methods that stop
    /// ovulation (round 4, Brandt F4, Ruiz F4).
    public static func score(usual: Double = 78, hrvDeltaPct: Double, restingHRDelta: Double, sleepShortfall: Int,
                             cycle: CycleHeartShift = .none) -> Int {
        let hrv = cycle.adjust(hrvDeltaPct: hrvDeltaPct), rhr = cycle.adjust(restingHRDelta: restingHRDelta)
        let s = usual + hrv * 1.0 - rhr * 1.5 - Double(max(sleepShortfall, 0)) * 0.06
        return Int(min(max(s, 1), 100).rounded())
    }
    /// `spread` is how much her own score usually moves day to day (the
    /// standard deviation of her recent scores, once there are 14 days). The
    /// bands scale with it, so someone whose score swings ±10 isn't told
    /// "Ready to push" or "Take it steady" for an ordinary day. Without it
    /// the bands are ±5 and −15.
    public static func label(_ score: Int, usual: Int, spread: Double? = nil) -> String {
        level(score, usual: usual, spread: spread).label
    }

    /// The four recovery bands. Every screen that names a recovery (the
    /// label, the Watch, the effort target on Energy) goes through this, so
    /// one score never gets two different names (Priya N4).
    public enum Level: Int, Sendable, CaseIterable {
        case push, onTrack, steady, easy
        /// "Ready to push", "On track", "Take it steady", "Go easy today".
        public var label: String {
            switch self {
            case .push: return "Ready to push"
            case .onTrack: return "On track"
            case .steady: return "Take it steady"
            case .easy: return "Go easy today"
            }
        }
        /// The effort target for training: "Push", "As planned", "Steady", "Go easy".
        public var effort: String {
            switch self {
            case .push: return "Push"
            case .onTrack: return "As planned"
            case .steady: return "Steady"
            case .easy: return "Go easy"
            }
        }
    }

    public static func level(_ score: Int, usual: Int, spread: Double? = nil) -> Level {
        let k = band(spread: spread)
        let d = Double(score - usual)
        if d >= k { return .push }
        if d > -k { return .onTrack }
        if d > -3 * k { return .steady }
        return .easy
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
    /// The period length used until her own logs give one.
    public static let typicalPeriodLength = 5

    /// Days from the estimated ovulation day to the next period. The second
    /// half of the cycle averages about 12–13 days and varies (7–17 days in
    /// Bull 2019), so ovulation is placed at length − 13, and only ever shown
    /// as a rough mid-cycle estimate (Okafor J).
    public static let daysFromOvulationToPeriod = 13

    /// Estimated ovulation day for a cycle of `length` days.
    public static func ovulationDay(length: Int) -> Int { length - daysFromOvulationToPeriod }

    public static func phase(day: Int, length: Int = 29, periodLength: Int = typicalPeriodLength) -> CyclePhase {
        guard day >= 1 else { return .unknown }
        let ovulation = ovulationDay(length: length)
        switch day {
        case 1...max(periodLength, 1): return .period
        case ..<(ovulation - 1): return .follicular
        case (ovulation - 1)...(ovulation + 1): return .ovulation
        default: return .luteal
        }
    }
    /// The last 7 days before the next period (day length − 6 to length),
    /// when PMS and lighter sleep are most common (Okafor K).
    public static func isLateLuteal(day: Int, length: Int = 29) -> Bool { phase(day: day, length: length) == .luteal && day >= length - 6 }

    /// Usual cycle length (median of the gaps between period starts that
    /// fall in 20–45 days). Nil when there are no such gaps: callers must not
    /// make one up. See `lengths` for cycles that run longer.
    public static func averageLength(periodStarts: [Date], calendar: Calendar = .current) -> Int? {
        lengths(periodStarts: periodStarts, calendar: calendar).usual
    }

    /// Her usual period length: the median length of her most recent
    /// periods (up to 6), from the days she logged bleeding. Bleeding days
    /// with at most one unlogged day between them count as one period.
    /// Kept to 2–10 days. Nil until at least one period of 2+ days is logged
    /// (callers then use `typicalPeriodLength`). Sam N10: a fixed 5 showed a
    /// logged day 6 as follicular and predicted periods a day short.
    public static func periodLength(bleedDays: [Date], calendar: Calendar = .current) -> Int? {
        let days = Set(bleedDays.map { calendar.startOfDay(for: $0) }).sorted()
        guard let first = days.first else { return nil }
        var runs: [Int] = []
        var start = first, last = first
        for d in days.dropFirst() {
            let gap = calendar.dateComponents([.day], from: last, to: d).day ?? 99
            if gap <= 2 {
                last = d
            } else {
                runs.append((calendar.dateComponents([.day], from: start, to: last).day ?? 0) + 1)
                start = d; last = d
            }
        }
        runs.append((calendar.dateComponents([.day], from: start, to: last).day ?? 0) + 1)
        let periods = runs.filter { $0 >= 2 }.suffix(6).map(Double.init)
        guard let m = periods.median else { return nil }
        return min(max(Int(m.rounded()), 2), 10)
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

    /// How many recent cycles the usual length is taken from (about a year).
    public static let recentCycles = 12

    /// `since`: the day she last changed birth control. Only cycles that
    /// start on or after it count, so pill bleeds and the months on a method
    /// never set her natural length (Okafor M). The usual length uses her
    /// most recent `recentCycles` cycles.
    public static func lengths(periodStarts: [Date], since: Date? = nil, calendar: Calendar = .current) -> Lengths {
        var s = periodStarts.sorted()
        if let since { s = s.filter { $0 >= calendar.startOfDay(for: since) } }
        guard s.count >= 2 else { return Lengths(gaps: [], usual: nil, runLong: false) }
        let gaps = Array(zip(s, s.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day ?? 0 }.suffix(recentCycles))
        let normal = gaps.filter { (20...45).contains($0) }.map(Double.init)
        let long = gaps.filter { $0 > 45 }.count
        return Lengths(gaps: gaps, usual: normal.median.map { Int($0.rounded()) }, runLong: long * 2 > gaps.count)
    }

    /// Patterns in her natural cycle lengths that are worth mentioning to a
    /// clinician (Okafor L): cycles shorter than 21 or longer than 35 days,
    /// lengths that vary by more than FIGO's 7–9 days, or fewer than 8
    /// periods in a year. One odd cycle now and then is common, so a single
    /// short or long one is reported but not flagged.
    public struct Pattern: Hashable, Sendable {
        /// The recent cycles looked at (up to 6), oldest first.
        public var recent: [Int]
        /// How many of them were under 21 or over 35 days.
        public var outOfRange: Int
        /// Longest minus shortest of the recent cycles (3 or more), else nil.
        public var spread: Int?
        /// The spread above which cycles count as irregular for her age.
        public var spreadLimit: Int
        /// Her history covers a year and has fewer than 8 period starts in it.
        public var fewPerYear: Bool

        public var spreadIsWide: Bool { (spread ?? 0) > spreadLimit }
        /// Two or more out-of-range cycles, a wide spread, or few periods.
        public var worthMentioning: Bool { outOfRange >= 2 || spreadIsWide || fewPerYear }
        /// Anything to say at all (including a single odd cycle).
        public var hasNote: Bool { outOfRange > 0 || worthMentioning }
    }

    /// Normal variation in cycle length (FIGO 2018): up to 9 days at 18–25
    /// and 42–45, up to 7 days at 26–41. 9 when her age isn't known, so
    /// a student isn't flagged for a normal spread.
    public static func spreadLimit(ageYears: Int?) -> Int {
        guard let a = ageYears else { return 9 }
        return (26...41).contains(a) ? 7 : 9
    }

    public static func pattern(periodStarts: [Date], since: Date? = nil, ageYears: Int? = nil,
                               now: Date = .now, calendar: Calendar = .current) -> Pattern {
        var s = periodStarts.map { calendar.startOfDay(for: $0) }.sorted()
        if let since { s = s.filter { $0 >= calendar.startOfDay(for: since) } }
        let gaps = zip(s, s.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day ?? 0 }
        let recent = Array(gaps.suffix(6))
        let out = recent.filter { $0 < 21 || $0 > 35 }.count
        let spread = recent.count >= 3 ? (recent.max() ?? 0) - (recent.min() ?? 0) : nil
        let yearAgo = calendar.date(byAdding: .day, value: -365, to: calendar.startOfDay(for: now)) ?? now
        let coversYear = (s.first.map { $0 <= yearAgo }) ?? false
        let inYear = s.filter { $0 > yearAgo }.count
        return Pattern(recent: recent, outOfRange: out, spread: spread,
                       spreadLimit: spreadLimit(ageYears: ageYears), fewPerYear: coversYear && inYear < 8)
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
    /// How many days were in the better and the lower half.
    public var betterDays: Int = 0
    public var lowerDays: Int = 0
    /// Both halves have at least `HabitEffect.minimumNights` days, the same
    /// minimum every other comparison uses. A single week (3 vs 3) never
    /// does, so its habits are hints, not a pattern (round 3, N6).
    public var enoughForPattern: Bool { betterDays >= HabitEffect.minimumNights && lowerDays >= HabitEffect.minimumNights }

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
                         bestDayHabits: habits, worstDayIssues: issues, habitsFromCheckIns: byCheckIn,
                         betterDays: top.count, lowerDays: bottom.count)
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
    /// Planned minutes asleep that night (never less than her need).
    public var asleep: Int = 0
    /// The wake time ends a whole sleep cycle.
    public var endsCycle: Bool = true
}

public enum ExamPlanner {
    /// Grogginess after waking, in minutes: about 30 after a light-sleep
    /// wake, up to an hour after deep sleep. The energy curve uses the same.
    public static let grogginessMinutes = 30
    public static let grogginessMinutesDeep = 60

    /// Plans the nights before an exam. Exam morning wakes at least
    /// `clearHeadMinutes` before the start so grogginess has passed.
    /// `caffeineCutoff`: her own cutoff for the study days (it's earlier on
    /// the combined pill, ring or patch); 2pm when not given.
    ///
    /// Each night plans whole sleep cycles of her own `cycleLength`, rounded
    /// up so it never plans less than her `need` (Park 2, Liu 11). When the
    /// extra cycle would add more than 25 minutes past her need (and move
    /// bedtime that much earlier), it plans exactly her need instead, the
    /// same 25-minute rule as the wake planner. The smart alarm window is the
    /// same shape as the everyday one: `windowLength` minutes before the
    /// wake to 3 after.
    public static func plan(examStart: Minutes, daysUntil: Int, usualBedtime: Minutes, latency: Int = 12, cycleLength: Int = 92, need: Int, energyTemplate: EnergyDay, clearHeadMinutes: Int = 70, caffeineCutoff: Minutes? = nil, windowLength: Int = 22) -> [ExamDayPlan] {
        let cycle = max(cycleLength, 1)
        let cycles = max(1, Int((Double(need) / Double(cycle)).rounded(.up)))
        let endsCycle = cycles * cycle - need <= WakePlanner.maxCycleTrade
        let sleep = endsCycle ? cycles * cycle : need
        var days: [ExamDayPlan] = []
        for offset in stride(from: -daysUntil, through: 0, by: 1) {
            let isExam = offset == 0
            // Exam morning: up by the clear-head time. Other nights: her
            // usual bedtime, or earlier, never later.
            let deadline = isExam ? examStart - clearHeadMinutes : usualBedtime + latency + sleep
            // Rounded down to 5 minutes: "bed by 11:20pm", not 11:23pm.
            let bed = min(usualBedtime, Int((Double(deadline - sleep - latency) / 5).rounded(.down)) * 5)
            let wake = bed + latency + sleep
            let blocks = isExam ? [] : [energyTemplate.zone(.morningPeak)?.range, energyTemplate.zone(.secondWind)?.range].compactMap { $0 }
            days.append(ExamDayPlan(dayOffset: offset, bedtimeBefore: bed, wake: wake,
                                    alarmWindow: TimeRange(wake - windowLength, wake + 3), studyBlocks: blocks,
                                    caffeineBy: isExam ? examStart - 45 : (caffeineCutoff ?? 840),
                                    asleep: sleep, endsCycle: endsCycle))
        }
        return days
    }
}

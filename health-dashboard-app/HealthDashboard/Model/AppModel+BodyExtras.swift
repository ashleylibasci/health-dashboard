import Foundation
import HealthCore

/// Derived values for the Body, Cycle, Fitness, Calories and Sick screens.
extension AppModel {
    // MARK: Birth control

    /// True when her method usually stops ovulation (combined pill, ring,
    /// patch, implant, shot). No screen should then mention ovulation as
    /// something that happens to her.
    var ovulationStopped: Bool { store.birthControl?.ovulation == .stopped }

    /// Pill, ring or patch: where she is in the pack.
    struct PackState: Hashable {
        var day: Int
        var activeDays: Int
        var packLength: Int
        /// False for continuous use (no break week, so no withdrawal bleed is due).
        var hasBreak: Bool { activeDays < packLength }
        var isBreak: Bool { hasBreak && day > activeDays }
        /// Days until the break week starts (0 while in it). Nil with no break week.
        var daysToBreak: Int? { hasBreak ? (isBreak ? 0 : activeDays - day + 1) : nil }
        /// Days until a new pack starts.
        var daysToNewPack: Int { packLength - day + 1 }
    }

    var packState: PackState? {
        if case let .pack(day, activeDays, packLength) = cycleDisplay {
            return PackState(day: day, activeDays: activeDays, packLength: packLength)
        }
        return nil
    }

    /// Pack day `offset` days from today (1…packLength).
    func packDay(offset: Int) -> Int? {
        guard let p = packState, p.packLength > 0 else { return nil }
        let raw = (p.day - 1 + offset) % p.packLength
        return (raw + p.packLength) % p.packLength + 1
    }

    /// The date the next break week (withdrawal bleed) starts, or today if
    /// she's in it. Nil with continuous use.
    var nextBreakStart: Date? {
        guard let days = packState?.daysToBreak else { return nil }
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: .now))
    }

    /// "Active pills", "Ring in", "Patch on".
    var packActiveName: String {
        switch store.birthControl {
        case .ring?: return "Ring in"
        case .patch?: return "Patch on"
        default: return "Active pills"
        }
    }

    /// "Break week" for a 7-day break, "Break days" for a shorter one (24+4).
    var packBreakName: String {
        guard let p = packState, p.hasBreak else { return "Break week" }
        return p.packLength - p.activeDays >= 7 ? "Break week" : "Break days"
    }

    /// One short line for rows and tiles: "Day 22 · Luteal",
    /// "Pack day 16 · Active pills", "Implant · no phases"…
    var cycleSummaryLine: String? {
        switch cycleDisplay {
        case let .phases(day, _, phase):
            return "Day \(day) \u{00B7} \(BodyLogStyle.phaseName(phase, birthControl: store.birthControl))"
        case let .overdue(day, typical):
            return "Day \(day) \u{00B7} longer than " + (cycleLengthIsPersonal ? "your usual \(typical) days" : "a typical \(typical) days")
        case let .pack(day, activeDays, packLength):
            if activeDays >= packLength { return "Pack day \(day) \u{00B7} Continuous" }
            return "Pack day \(day) \u{00B7} " + (day > activeDays ? packBreakName : packActiveName)
        case let .suppressed(bc):
            return "\(bc.rawValue) \u{00B7} no phases"
        case let .irregular(days):
            return days.map { "\($0) day\($0 == 1 ? "" : "s") since your last period started" } ?? "Log a period to start"
        case .notTracking:
            return nil
        }
    }

    // MARK: Cycle history

    /// Period starts she logged in the app (bleeding days, not spotting).
    var loggedPeriodStarts: [Date] { Self.mergedPeriodStarts(health: [], logged: store.data.flowLog) }

    /// Every period start known: Apple Health's and the ones logged here.
    var allPeriodStarts: [Date] { Self.mergedPeriodStarts(health: healthPeriodStarts, logged: store.data.flowLog) }

    /// Gaps between period starts, oldest first (for irregular cycles), from
    /// Apple Health and the app's own logs together.
    var loggedCycleLengths: [Int] {
        let s = allPeriodStarts
        guard s.count >= 2 else { return [] }
        let cal = Calendar.current
        return zip(s, s.dropFirst()).compactMap { cal.dateComponents([.day], from: $0, to: $1).day }
    }

    /// Her own sleep, HRV and resting heart rate by cycle phase, compared
    /// with her overall average. Nil until there are real nights in at least
    /// two cycles (sample data has no real cycle in it) or when phases don't
    /// apply.
    struct PhaseAverage: Hashable {
        var nights: Int
        var sleepDelta: Int
        var hrvDeltaPct: Double?
        var restingHRDelta: Double?
    }

    /// Period starts known to the app: Apple Health's plus the ones logged here.
    private var knownPeriodStarts: [Date] { allPeriodStarts }

    /// Each night is placed in its real cycle (from known period starts), never
    /// by wrapping today's cycle day backwards. Nights before the first known
    /// start, or more than 3 days past that cycle's length, are left out.
    var phaseAverages: [CyclePhase: PhaseAverage]? {
        guard !usingSampleData else { return nil }
        let typical: Int
        switch cycleDisplay {
        case let .phases(_, length, _): typical = length
        case let .overdue(_, length): typical = length
        default: return nil
        }
        guard nights.count >= typical * 2 else { return nil }
        let cal = Calendar.current
        let starts = knownPeriodStarts
        guard starts.count >= 2 else { return nil }
        var groups: [CyclePhase: [NightRecord]] = [:]
        for n in nights {
            let wake = cal.startOfDay(for: n.wakeDay)
            guard let i = starts.lastIndex(where: { $0 <= wake }) else { continue }
            let day = (cal.dateComponents([.day], from: starts[i], to: wake).day ?? 0) + 1
            let length = i + 1 < starts.count ? (cal.dateComponents([.day], from: starts[i], to: starts[i + 1]).day ?? typical) : typical
            guard day <= length + CycleDisplay.overdueGraceDays else { continue }
            groups[CycleEstimator.phase(day: day, length: length, periodLength: periodLength), default: []].append(n)
        }
        let allSleep = nights.map { Double($0.asleepMinutes) }.mean ?? 0
        var out: [CyclePhase: PhaseAverage] = [:]
        for (phase, ns) in groups where ns.count >= 3 {
            let sleep = (ns.map { Double($0.asleepMinutes) }.mean ?? allSleep) - allSleep
            out[phase] = PhaseAverage(nights: ns.count, sleepDelta: Int(sleep.rounded()),
                                      hrvDeltaPct: ns.compactMap(\.outcome.hrvDeltaPct).mean,
                                      restingHRDelta: ns.compactMap(\.outcome.restingHRDelta).mean)
        }
        return out
    }

    // MARK: Trends

    struct TrendPoint: Identifiable, Hashable {
        var id: Date { date }
        var date: Date
        var hrv: Double?
        var restingHR: Double?
        var asleep: Int
    }

    /// The last 14 nights with HRV and resting heart rate rebuilt from the
    /// differences against her baseline.
    var bodyTrend: [TrendPoint] {
        let recent = nights.sorted { $0.wakeDay < $1.wakeDay }.suffix(14)
        let hrvBase = baselineHRV
        return recent.map { n in
            TrendPoint(date: n.wakeDay,
                       hrv: n.outcome.hrvDeltaPct.map { hrvBase * (1 + $0 / 100) },
                       restingHR: n.outcome.restingHRDelta.map { baselineRestingHR + $0 },
                       asleep: n.asleepMinutes)
        }
    }

    // MARK: Fitness and calories

    var vo2MaxPeak: (date: Date, value: Double)? { vo2MaxHistory.max { $0.value < $1.value } }

    /// Calories stay hidden for an eating-disorder history, whatever the toggle says.
    var caloriesHiddenByCondition: Bool { store.data.conditions.contains("Eating-disorder history") }
    var showsCalories: Bool { store.data.showCalories && !caloriesHiddenByCondition }

    /// Whether today is in the luteal phase of a natural cycle (warmer nights,
    /// higher resting burn).
    /// Not once she's past her usual length (the period is due around now).
    var inLutealPhase: Bool { trackedCyclePhase == .luteal && !cycleDisplay.isPastUsualLength }
}

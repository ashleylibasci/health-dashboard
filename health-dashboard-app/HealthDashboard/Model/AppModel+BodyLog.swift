import Foundation
import HealthCore

/// Cycle values shared by the Body, Log and Cycle screens. Everything goes
/// through `cycleDisplay`, so birth control that stops ovulation never shows
/// ovulation, luteal days or a period countdown.
extension AppModel {
    /// Natural-cycle phase today. Nil when she isn't tracking, has no period
    /// logged yet, is irregular/PCOS, is past her usual length (overdue), or
    /// uses a method with a pill pack or one that stops ovulation.
    var trackedCyclePhase: CyclePhase? {
        if case let .phases(_, _, phase) = cycleDisplay { return phase }
        return nil
    }

    /// Days since her last period started (0 on the first day), the one
    /// definition every screen uses. "Day N" of the cycle is this plus 1.
    var daysSinceLastPeriodStart: Int? { cycleDay.map { max($0 - 1, 0) } }

    /// Cycle day (1-based) `offset` days from today, for natural phases and
    /// the overdue state. Nil where it isn't known:
    /// - looking back past the start of this cycle (earlier cycles had their
    ///   own lengths; `phaseAverages` uses real period starts for those),
    /// - looking ahead once the period is due or overdue (no guessing when the
    ///   next one starts),
    /// - pill packs, suppressed bleeding and irregular cycles.
    /// Looking ahead within the cycle, the next cycle is predicted to start
    /// the day after day `length`.
    func predictedCycleDay(offset: Int) -> Int? {
        switch cycleDisplay {
        case let .phases(day, length, _):
            guard length > 0 else { return nil }
            let d = day + offset
            if offset <= 0 { return d >= 1 ? d : nil }
            if day > length { return nil }                 // due now: next start unknown
            return (d - 1) % length + 1
        case let .overdue(day, _):
            let d = day + offset
            return offset <= 0 && d >= 1 ? d : nil
        default:
            return nil
        }
    }

    /// Days until the next period is expected (0 on the day after her usual
    /// length). Nil once she's past her usual length (`periodDueAroundNow`
    /// for the 3 grace days, then overdue: no countdown either way), and
    /// whenever a countdown would be wrong: irregular cycles, PCOS, the pill
    /// pack (that bleed is a withdrawal bleed), methods that stop or blur
    /// periods, and the mini pill.
    var daysToPredictedPeriod: Int? {
        guard !hidesPeriodCountdown, case let .phases(day, length, _) = cycleDisplay, day <= length else { return nil }
        return length - day + 1
    }

    /// Past her usual length but not yet overdue (the 3 grace days): "Due
    /// around now" once, not "Period expected today" three days running,
    /// and no luteal adjustments. "Day 30 · around your usual length".
    var periodDueAroundNow: Bool {
        !hidesPeriodCountdown && cycleDisplay.isPastUsualLength
    }

    var predictedPeriodStart: Date? {
        guard let days = daysToPredictedPeriod else { return nil }
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: .now))
    }

    /// No countdowns or "late period" wording: irregular cycles, PCOS,
    /// overdue cycles, implant/shot (bleeding may be irregular or absent),
    /// the mini pill (bleeding is unpredictable) and pill packs (the
    /// break-week bleed has its own countdown, not a period one).
    var hidesPeriodCountdown: Bool {
        if store.data.cycleSetup == .irregular || store.data.conditions.contains("PCOS") { return true }
        switch cycleDisplay {
        case .phases: return store.birthControl == .miniPill
        default: return true
        }
    }

    // MARK: When to mention it to a clinician

    /// A natural cycle the care notes apply to: no method, or the copper IUD.
    /// Hormonal methods set their own bleeding pattern, so a long gap there
    /// is expected, not a sign.
    var cycleIsNatural: Bool {
        guard store.data.cycleSetup != .notTracking else { return false }
        guard let bc = store.birthControl else { return true }
        return bc == .copperIUD
    }

    /// 90 days or more since her last period started, on a natural cycle
    /// (Okafor E, Ruiz F1).
    var showsNoPeriodPrompt: Bool {
        cycleIsNatural && (daysSinceLastPeriodStart ?? 0) >= 90
    }

    /// Short or long cycles, a wide spread or few periods a year, from her
    /// natural cycles since her last method change (Okafor L).
    var cyclePatternNote: (title: String, text: String)? {
        guard cycleIsNatural else { return nil }
        let p = CycleEstimator.pattern(periodStarts: allPeriodStarts, since: store.data.methodChangedDate,
                                       ageYears: store.data.ageYears)
        guard p.hasNote else { return nil }
        var parts: [String] = []
        if p.outOfRange > 0 {
            parts.append(p.outOfRange == 1
                         ? "One of your last \(p.recent.count) cycles was shorter than 21 or longer than 35 days."
                         : "\(p.outOfRange) of your last \(p.recent.count) cycles were shorter than 21 or longer than 35 days.")
        }
        if p.spreadIsWide, let spread = p.spread {
            parts.append("Your recent cycles varied by \(spread) days; more than \(p.spreadLimit) counts as irregular.")
        }
        if p.fewPerYear { parts.append("You had fewer than 8 periods in the last year.") }
        if p.worthMentioning {
            parts.append("Worth mentioning to a clinician. It\u{2019}s common and easy to check, and your history here helps.")
            return ("Worth mentioning to a clinician", parts.joined(separator: " "))
        }
        parts.append("One like that now and then is common. If it keeps happening, mention it to a clinician.")
        return ("A cycle outside the usual range", parts.joined(separator: " "))
    }

    /// She changed birth control in the last 6 months and is now on a
    /// natural cycle: cycles may take a while to settle (Okafor M).
    var recentlyChangedMethod: Bool {
        guard cycleIsNatural, store.birthControl == nil, let changed = store.data.methodChangedDate else { return false }
        let days = Calendar.current.dateComponents([.day], from: changed, to: .now).day ?? 999
        return days <= 182
    }
}

import Foundation

/// Body-clock type, computed from tracked sleep the way the Munich ChronoType
/// Questionnaire does (Roenneberg): mid-sleep on free days, corrected for the
/// extra sleep people catch up on when they don't set an alarm.
public struct Chronotype: Hashable, Sendable {
    public enum Category: String, Sendable, CaseIterable {
        case veryEarly = "Very early type"
        case moderateMorning = "Moderate morning type"
        case intermediate = "Intermediate type"
        case moderateEvening = "Moderate evening type"
        case definiteEvening = "Definite evening type"
        case veryLate = "Very late type"
    }

    /// Mid-sleep on work days and free days, minutes after midnight.
    public var midSleepWork: Minutes
    public var midSleepFree: Minutes
    /// Sleep-corrected mid-sleep on free days (MSFsc).
    public var midSleepFreeCorrected: Minutes
    public var weeklyAverageSleep: Int
    /// Social jetlag: the shift between work-day and free-day mid-sleep.
    public var socialJetlag: Int
    public var category: Category

    public struct Night: Hashable, Sendable {
        public var onset: Minutes   // relative to wake-day midnight (negative = before midnight)
        public var wake: Minutes
        public init(onset: Minutes, wake: Minutes) { self.onset = onset; self.wake = wake }
        var duration: Int { wake - onset }
        var mid: Minutes { onset + duration / 2 }
    }

    public static func compute(workNights: [Night], freeNights: [Night], workDaysPerWeek: Int = 5) -> Chronotype? {
        guard !workNights.isEmpty, !freeNights.isEmpty else { return nil }
        func avg(_ xs: [Int]) -> Int { Int((Double(xs.reduce(0, +)) / Double(xs.count)).rounded()) }
        let sdW = avg(workNights.map(\.duration)), sdF = avg(freeNights.map(\.duration))
        let soF = avg(freeNights.map(\.onset))
        let msw = avg(workNights.map(\.mid)), msf = avg(freeNights.map(\.mid))
        let freeDays = 7 - workDaysPerWeek
        let sdWeek = (sdW * workDaysPerWeek + sdF * freeDays) / 7
        // MCTQ: correct only when free-day sleep is longer than work-day sleep.
        let msfsc = sdF > sdW ? soF + sdWeek / 2 : msf
        let wrapped = (msfsc + 1440) % 1440
        return Chronotype(midSleepWork: (msw + 1440) % 1440, midSleepFree: (msf + 1440) % 1440,
                          midSleepFreeCorrected: wrapped, weeklyAverageSleep: sdWeek,
                          socialJetlag: abs(msf - msw), category: category(for: wrapped))
    }

    public static func category(for msfsc: Minutes) -> Category {
        // Treat early-evening values (after noon) as before midnight.
        let h = Double(msfsc > 720 ? msfsc - 1440 : msfsc) / 60
        switch h {
        case ..<3: return .veryEarly
        case ..<4: return .moderateMorning
        case ..<5: return .intermediate
        case ..<6: return .moderateEvening
        case ..<7: return .definiteEvening
        default: return .veryLate
        }
    }
}

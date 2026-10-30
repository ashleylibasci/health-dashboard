import Foundation

/// Patterns (D-P2): nights with something (2+ drinks, an exam week, a
/// "Late study" tag) against the nights without it, from her own data.
/// The same shape as H-E4's `CaffeineSleepComparison`: nothing shows until
/// there are at least 20 nights with 5 on each side, and then only a
/// difference bigger than her normal night-to-night wobble. The words say
/// what happened ("your HRV averaged 9% lower"), never what caused it.
///
/// Things that happen mostly on weekends (parties, drinks) would otherwise
/// be credited with the weekend's longer sleep, so those are compared
/// within alarm mornings and within free mornings, as `lateNightEffect`
/// does, and pooled only when both have enough nights (`pooled`).
public struct PatternComparison: Hashable, Sendable {
    /// Nights before a pattern can show, and the fewest on each side
    /// (H-E4's numbers).
    public static let nightsNeeded = 20
    public static let nightsPerSide = 5
    /// How far the difference has to clear the wobble: more than twice the
    /// standard error of the difference between the two averages, the
    /// spread two groups of her nights that size would show by chance
    /// (about a 95% two-sided test).
    public static let wobbleMultiple = 2.0

    public var withCount: Int
    public var withoutCount: Int
    public var withMean: Double?
    public var withoutMean: Double?
    /// Average with, minus average without.
    public var difference: Double?
    /// Her night-to-night wobble for groups this size: the standard error of
    /// the difference (Welch), from each side's own spread.
    public var wobble: Double?
    /// The smallest difference worth a card for this measure.
    public var minimumSize: Double
    /// Pooled from alarm and free mornings: each of the two had at least
    /// `nightsPerSide` on each side. Always true for a plain comparison.
    public var strataQualify = true

    public var nights: Int { withCount + withoutCount }
    public var enoughNights: Bool {
        strataQualify && nights >= Self.nightsNeeded && withCount >= Self.nightsPerSide && withoutCount >= Self.nightsPerSide
    }
    /// At least `nightsPerSide` on each side.
    var bothSides: Bool { withCount >= Self.nightsPerSide && withoutCount >= Self.nightsPerSide }
    /// Enough nights, a difference past the wobble, and big enough to matter.
    public var shows: Bool {
        guard enoughNights, let d = difference, let w = wobble else { return false }
        return abs(d) > Self.wobbleMultiple * w && abs(d) >= minimumSize
    }
    /// How far past the wobble (for picking the clearest measure).
    var strength: Double {
        guard let d = difference, let w = wobble else { return 0 }
        return w > 0 ? abs(d) / w : (d == 0 ? 0 : .infinity)
    }

    public static func make(with a: [Double], without b: [Double], minimumSize: Double) -> PatternComparison {
        let ma = a.mean, mb = b.mean
        let wobble: Double? = {
            guard let va = a.variance, let vb = b.variance else { return nil }
            return (va / Double(a.count) + vb / Double(b.count)).squareRoot()
        }()
        return PatternComparison(withCount: a.count, withoutCount: b.count, withMean: ma, withoutMean: mb,
                                 difference: ma.flatMap { x in mb.map { x - $0 } }, wobble: wobble, minimumSize: minimumSize)
    }

    /// The alarm-morning and free-morning comparisons as one: each one's
    /// averages weighted by its smaller side (as `HabitEffect.compare(within:)`
    /// does), the wobble combined with the same weights. Shows nothing
    /// (`strataQualify` false) unless both have `nightsPerSide` on each side.
    public static func pooled(_ parts: [PatternComparison], minimumSize: Double) -> PatternComparison {
        let qualify = parts.count == 2 && parts.allSatisfy(\.bothSides)
        let usable = parts.filter { $0.withMean != nil && $0.withoutMean != nil && $0.wobble != nil }
        let weights = usable.map { Double(min($0.withCount, $0.withoutCount)) }
        let total = weights.reduce(0, +)
        func weighted(_ f: (PatternComparison) -> Double) -> Double? {
            total > 0 ? zip(usable, weights).map { f($0) * $1 }.reduce(0, +) / total : nil
        }
        let withMean = weighted { $0.withMean ?? 0 }, withoutMean = weighted { $0.withoutMean ?? 0 }
        let wobble = total > 0
            ? zip(usable, weights).map { pow(($0.wobble ?? 0) * $1, 2) }.reduce(0, +).squareRoot() / total
            : nil
        return PatternComparison(withCount: parts.map(\.withCount).reduce(0, +),
                                 withoutCount: parts.map(\.withoutCount).reduce(0, +),
                                 withMean: withMean, withoutMean: withoutMean,
                                 difference: withMean.flatMap { x in withoutMean.map { x - $0 } },
                                 wobble: wobble, minimumSize: minimumSize, strataQualify: qualify)
    }
}

/// What a pattern compares, read from a night.
public enum PatternMetric: String, CaseIterable, Hashable, Sendable {
    /// HRV against her usual, in percent.
    case hrv
    /// Resting heart rate against her usual, in bpm.
    case restingHR
    /// Minutes asleep.
    case asleep
    /// Bedtime to falling asleep, in minutes (capped at 3 hours, as H-E4).
    case fallAsleep
    /// The morning check-in, 1–5.
    case checkIn

    /// The smallest difference that gets a card: about the change each
    /// measure's own screens call a real change (HRV 5%, resting HR 2 bpm,
    /// 20 minutes of sleep, 10 minutes to fall asleep, half a check-in point).
    public var minimumSize: Double {
        switch self {
        case .hrv: return 5
        case .restingHR: return 2
        case .asleep: return 20
        case .fallAsleep: return 10
        case .checkIn: return 0.5
        }
    }

    public func value(_ n: NightRecord) -> Double? {
        switch self {
        case .hrv: return n.outcome.hrvDeltaPct
        case .restingHR: return n.outcome.restingHRDelta
        case .asleep: return Double(n.asleepMinutes)
        case .fallAsleep: return Double(min(max(n.sleepOnset - n.bedtime, 0), 180))
        case .checkIn: return n.outcome.checkIn
        }
    }

    /// What happened, in her words: "your HRV averaged 9% lower",
    /// "you slept 42 min less". `difference` is with minus without.
    public func phrase(_ difference: Double) -> String {
        let up = difference > 0
        switch self {
        case .hrv:
            return "your HRV averaged \(Int(abs(difference).rounded()))% \(up ? "higher" : "lower")"
        case .restingHR:
            return "your resting heart rate averaged \(Int(abs(difference).rounded())) bpm \(up ? "higher" : "lower")"
        case .asleep:
            return "you slept \(Clock.duration(Int(difference.rounded()))) \(up ? "more" : "less")"
        case .fallAsleep:
            let m = Int(abs(difference).rounded())
            return up ? "you took \(m)\u{00A0}min longer to fall asleep" : "you fell asleep \(m)\u{00A0}min faster"
        case .checkIn:
            return "you rated your mornings \(String(format: "%.1f", abs(difference))) \(up ? "higher" : "lower") out of 5"
        }
    }
}

/// One factor's comparison: the measure where her nights differ most
/// clearly, or how far along it is.
public struct Pattern: Hashable, Sendable {
    public var metric: PatternMetric
    public var comparison: PatternComparison
    /// Compared within alarm mornings and within free mornings: those two,
    /// in that order. Nil for a plain comparison.
    public var strata: [PatternComparison]? = nil

    /// "On nights after 2+ drinks, your HRV averaged 9% lower than on
    /// other nights." Nil until it shows.
    public func sentence(context: String) -> String? {
        guard comparison.shows, let d = comparison.difference else { return nil }
        return "\(context), \(metric.phrase(d)) than on other nights."
    }

    /// The clearest of `metrics` for nights where `flag` is true against
    /// nights where it's false (nil: not known, left out). Prefers one that
    /// shows; otherwise the one with the most nights, so "3 of 5 nights"
    /// counts honestly. Nil without metrics.
    ///
    /// `withinAlarmMornings`: compare within alarm mornings and within free
    /// mornings (`NightRecord.alarmUsed`) and pool the two (`pooled`), for
    /// anything that could be mostly a weekend thing.
    public static func find(_ nights: [NightRecord], metrics: [PatternMetric], withinAlarmMornings: Bool = false,
                            flag: (NightRecord) -> Bool?) -> Pattern? {
        let known = nights.compactMap { n in flag(n).map { (n, $0) } }
        func compare(_ m: PatternMetric, _ subset: [(NightRecord, Bool)]) -> PatternComparison {
            .make(with: subset.filter(\.1).compactMap { m.value($0.0) },
                  without: subset.filter { !$0.1 }.compactMap { m.value($0.0) }, minimumSize: m.minimumSize)
        }
        let candidates = metrics.map { m -> Pattern in
            guard withinAlarmMornings else { return Pattern(metric: m, comparison: compare(m, known)) }
            let strata = [compare(m, known.filter { $0.0.alarmUsed }), compare(m, known.filter { !$0.0.alarmUsed })]
            return Pattern(metric: m, comparison: .pooled(strata, minimumSize: m.minimumSize), strata: strata)
        }
        if let best = candidates.filter(\.comparison.shows).max(by: { $0.comparison.strength < $1.comparison.strength }) {
            return best
        }
        return candidates.max { ($0.comparison.withCount, $0.comparison.nights) < ($1.comparison.withCount, $1.comparison.nights) }
    }
}

import Foundation

/// Patterns (D-P2): nights with something (2+ drinks, an exam week, a
/// "Late study" tag) against the nights without it, from her own data.
/// The same shape as H-E4's `CaffeineSleepComparison`: nothing shows until
/// there are at least 20 nights with 5 on each side, and then only a
/// difference bigger than her normal night-to-night wobble. The words say
/// what happened ("your HRV averaged 9% lower"), never what caused it.
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

    public var nights: Int { withCount + withoutCount }
    public var enoughNights: Bool {
        nights >= Self.nightsNeeded && withCount >= Self.nightsPerSide && withoutCount >= Self.nightsPerSide
    }
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
    public static func find(_ nights: [NightRecord], metrics: [PatternMetric], flag: (NightRecord) -> Bool?) -> Pattern? {
        let known = nights.compactMap { n in flag(n).map { (n, $0) } }
        let candidates = metrics.map { m -> Pattern in
            let a = known.filter(\.1).compactMap { m.value($0.0) }
            let b = known.filter { !$0.1 }.compactMap { m.value($0.0) }
            return Pattern(metric: m, comparison: .make(with: a, without: b, minimumSize: m.minimumSize))
        }
        if let best = candidates.filter(\.comparison.shows).max(by: { $0.comparison.strength < $1.comparison.strength }) {
            return best
        }
        return candidates.max { ($0.comparison.withCount, $0.comparison.nights) < ($1.comparison.withCount, $1.comparison.nights) }
    }
}

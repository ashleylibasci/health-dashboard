import Foundation

// MARK: - The cycle's own shift in heart readings

/// How a natural cycle moves resting heart rate and HRV on its own, against
/// a 30-day median that mixes every phase. After ovulation (luteal phase)
/// resting heart rate runs higher and HRV lower; in the first week of a
/// period the reverse. The swing across a cycle is about 2.7 bpm and 8% HRV
/// (Jasinski 2024), so half of it each way from the middle.
/// Methods that stop ovulation (pill, ring, patch, implant, shot) have no
/// such swing: `make` gives `.none` for them because `CycleDisplay` never
/// shows phases there.
public enum CycleHeartShift: String, Sendable, CaseIterable {
    case none, period, luteal

    /// The first days of a period that count as "period week" here.
    public static let periodDays = 7

    /// Expected change in resting heart rate (bpm) against her 30-day median.
    public var restingHR: Double {
        switch self {
        case .none: 0
        case .period: -1.5
        case .luteal: 1.5
        }
    }

    /// Expected change in HRV (%) against her 30-day median.
    public var hrvPct: Double {
        switch self {
        case .none: 0
        case .period: 4
        case .luteal: -4
        }
    }

    /// Today's shift from what the cycle screen shows: only a natural cycle
    /// with a known phase (not past her usual length, irregular or overdue).
    public static func make(_ display: CycleDisplay, periodLength: Int = CycleEstimator.typicalPeriodLength) -> CycleHeartShift {
        guard case let .phases(day, length, _) = display, day <= length else { return .none }
        return forDay(day, length: length, periodLength: periodLength)
    }

    /// The shift on cycle `day` (1 = first day of the period) of a natural
    /// cycle of `length` days. Nothing past the cycle's length.
    public static func forDay(_ day: Int, length: Int, periodLength: Int = CycleEstimator.typicalPeriodLength) -> CycleHeartShift {
        guard day >= 1, day <= length else { return .none }
        if day <= periodDays { return .period }
        return CycleEstimator.phase(day: day, length: length, periodLength: periodLength) == .luteal ? .luteal : .none
    }

    /// Her HRV change with the cycle's own part taken out.
    public func adjust(hrvDeltaPct: Double) -> Double { hrvDeltaPct - hrvPct }
    /// Her resting heart rate change with the cycle's own part taken out.
    public func adjust(restingHRDelta: Double) -> Double { restingHRDelta - restingHR }
}

// MARK: - Bands against her own spread

/// The one set of cutoffs every screen uses to call resting heart rate or
/// HRV "up", "down" or "usual", so Today, Recovery and Body never disagree.
public enum HeartBands {
    /// Resting heart rate this many beats above her usual counts as "up",
    /// everywhere (round 4, Brandt F8).
    public static let restingHRUp = 3.0
    /// This many beats below her usual counts as "below".
    public static let restingHRDown = 2.0

    public enum Level: String, Sendable, CaseIterable { case wellBelow, below, usual, above }

    /// Resting heart rate: `.above` at +3 bpm or more, `.below` at −2 or less.
    public static func restingHR(delta: Double) -> Level {
        if delta >= restingHRUp { return .above }
        if delta <= -restingHRDown { return .below }
        return .usual
    }

    /// HRV against her own day-to-day spread (`spreadPct`, the standard
    /// deviation of her mornings as a % of her usual). Without one the
    /// fixed cutoffs: −10% or more well below, −3% below, +5% above. With
    /// one, a change has to clear her own spread too, so someone whose HRV
    /// swings ±20% isn't told "under strain" on an ordinary morning.
    public static func hrv(deltaPct: Double, spreadPct: Double? = nil) -> Level {
        let sd = max(spreadPct ?? 0, 0)
        if deltaPct <= -max(10, sd) { return .wellBelow }
        if deltaPct < -max(3, sd * 0.5) { return .below }
        if deltaPct >= max(5, sd * 0.5) { return .above }
        return .usual
    }

    /// Her day-to-day spread (standard deviation), once there are at least
    /// 10 days. Nil before that.
    public static func spread(_ values: [Double]) -> Double? {
        guard values.count >= 10 else { return nil }
        return values.standardDeviation
    }

    /// Her own usual range: the 10th to 90th percentile of her recent days,
    /// once there are at least 10. Nil before that, or when every day was
    /// the same.
    public static func usualRange(_ values: [Double]) -> ClosedRange<Double>? {
        guard values.count >= 10 else { return nil }
        let s = values.sorted()
        func pct(_ p: Double) -> Double {
            let i = p * Double(s.count - 1)
            let lo = Int(i.rounded(.down)), hi = Int(i.rounded(.up))
            return s[lo] + (s[hi] - s[lo]) * (i - Double(lo))
        }
        let a = pct(0.1), b = pct(0.9)
        return b > a ? a...b : nil
    }

    /// Where `value` sits on a dial whose middle 80% is her own usual range:
    /// the bottom of her range at 0.1, the top at 0.9, clamped to 0.03–1.
    public static func gaugeFraction(_ value: Double, range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0.5 }
        return min(max(0.1 + 0.8 * (value - range.lowerBound) / span, 0.03), 1)
    }
}

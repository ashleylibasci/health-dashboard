import Foundation

/// How much sleep a person needs, learned from their own nights.
///
/// Three independent signals are combined, then kept inside research limits:
///
/// 1. **Rebound on free nights.** After a stretch of nights with no alarm, once
///    any debt is paid off, sleep length settles at the true need
///    (the sleep-extension approach of Kitamura et al., 2016; RISE uses a
///    similar "rebound" signal).
/// 2. **Where more sleep stops helping.** For each next-day measure (HRV,
///    resting heart rate, energy, reaction time) a hinge model
///    `y = a + b · min(hours − knee, 0)` is fit; the knee is where extra sleep
///    stops improving that measure.
/// 3. **How you felt**, used only as a cross-check with a low weight: people
///    under chronic restriction report feeling fine while performance keeps
///    falling (Van Dongen et al., 2003).
///
/// With little data the estimate leans on the adult average (8h) and widens.
public struct SleepNeedEstimate: Hashable, Codable, Sendable {
    public enum Confidence: String, Codable, Sendable { case learning, fair, good }

    public var minutes: Int
    public var range: TimeRange
    public var confidence: Confidence
    public var nights: Int
    public var methods: [Method]

    public struct Method: Hashable, Codable, Sendable {
        public enum Kind: String, Codable, Sendable { case rebound, hrv, restingHR, energy, reaction, checkIn, prior }
        public var kind: Kind
        public var minutes: Int
        public var weight: Double
        public var samples: Int
        /// How much of the measure the fitted curve explains (knee fits only).
        public var rSquared: Double? = nil
        /// Strong enough on its own to count toward "Fairly sure": a knee fit
        /// that explains at least 25% from 28+ nights. A noisy measure can
        /// look like a knee by chance when 43 knees are tried, so the
        /// weaker fits still nudge the estimate but don't raise confidence.
        public var isStrong: Bool { (rSquared ?? 0) >= SleepNeedEstimator.strongFitRSquared && samples >= SleepNeedEstimator.strongFitNights }
    }

    /// The point where feeling better stops (useful to show it plateaus earlier).
    public var subjectiveKnee: Int? { methods.first { $0.kind == .checkIn }?.minutes }
}

/// A fitted "more helps until the knee, then flat" curve.
public struct KneeFit: Hashable, Sendable {
    public var knee: Double        // minutes asleep
    public var plateau: Double     // value at and above the knee
    public var slopePerHour: Double
    public var rSquared: Double
    public var samples: Int

    public func value(atMinutes x: Double) -> Double {
        plateau + slopePerHour * min(x - knee, 0) / 60
    }
}

public enum SleepNeedEstimator {
    public static let populationPrior = 480       // 8h, the adult average
    public static let researchLimits = 360...600  // 6h to 10h
    /// A knee fit counts toward confidence only from this R² and night count.
    public static let strongFitRSquared = 0.25
    public static let strongFitNights = 28

    /// Least-squares hinge fit over candidate knees between 6h and 9h 30m.
    /// `higherIsBetter` decides which slope sign counts as "more sleep helps".
    public static func fitKnee(_ points: [(minutes: Double, value: Double)], higherIsBetter: Bool) -> KneeFit? {
        guard points.count >= 12 else { return nil }
        let ys = points.map(\.value)
        guard let yMean = ys.mean else { return nil }
        let ssTot = ys.map { ($0 - yMean) * ($0 - yMean) }.reduce(0, +)
        guard ssTot > 0 else { return nil }

        var best: KneeFit?
        var bestSSE = Double.infinity
        for knee in stride(from: 360.0, through: 570.0, by: 5.0) {
            // Regress y on h = min(x - knee, 0) / 60.
            let hs = points.map { min($0.minutes - knee, 0) / 60 }
            guard let hMean = hs.mean else { continue }
            let sxx = hs.map { ($0 - hMean) * ($0 - hMean) }.reduce(0, +)
            // Need points on the short side of the knee to estimate a slope.
            guard sxx > 1e-9, hs.filter({ $0 < 0 }).count >= 4, hs.filter({ $0 == 0 }).count >= 4 else { continue }
            let sxy = zip(hs, ys).map { ($0 - hMean) * ($1 - yMean) }.reduce(0, +)
            let b = sxy / sxx
            let a = yMean - b * hMean
            var sse = 0.0
            for (h, y) in zip(hs, ys) { let r: Double = y - (a + b * h); sse += r * r }
            if sse < bestSSE {
                bestSSE = sse
                best = KneeFit(knee: knee, plateau: a, slopePerHour: b, rSquared: 1 - sse / ssTot, samples: points.count)
            }
        }
        guard let fit = best else { return nil }
        // The slope must point the healthy way and explain something.
        let helps = higherIsBetter ? fit.slopePerHour > 0 : fit.slopePerHour < 0
        return helps && fit.rSquared >= 0.15 ? fit : nil
    }

    /// Sleep within this many minutes of the need counts as meeting it,
    /// everywhere the app says "met your need" (streaks, recap, badges).
    public static let metNeedToleranceMinutes = 15
    public static func metNeed(asleep: Int, need: Int) -> Bool { asleep >= need - metNeedToleranceMinutes }

    /// Median sleep on free (no-alarm) nights from the second night of a run
    /// of two or more in a row, once the first night's catch-up sleep is
    /// done. A normal weekend (two free nights) gives one sample.
    public static func reboundEstimate(_ nights: [NightRecord], calendar: Calendar = .current) -> (minutes: Int, samples: Int)? {
        let sorted = nights.sorted { $0.wakeDay < $1.wakeDay }
        var settled: [Double] = []
        var run: [NightRecord] = []
        func flush() {
            if run.count >= 2 { settled += run.dropFirst(1).map { Double($0.asleepMinutes) } }
            run = []
        }
        for night in sorted {
            if !night.alarmUsed, let last = run.last,
               calendar.dateComponents([.day], from: calendar.startOfDay(for: last.wakeDay), to: calendar.startOfDay(for: night.wakeDay)).day == 1 {
                run.append(night)
            } else {
                flush()
                if !night.alarmUsed { run = [night] }
            }
        }
        flush()
        guard settled.count >= 3, let m = settled.median else { return nil }
        return (Int(m.rounded()), settled.count)
    }

    public static func estimate(from nights: [NightRecord], userAdjustment: Int = 0) -> SleepNeedEstimate {
        var methods: [SleepNeedEstimate.Method] = []
        func add(_ kind: SleepNeedEstimate.Method.Kind, _ fit: KneeFit?, weight: Double) {
            guard let fit else { return }
            methods.append(.init(kind: kind, minutes: Int(fit.knee), weight: weight * max(fit.rSquared, 0.2), samples: fit.samples,
                                 rSquared: fit.rSquared))
        }
        func points(_ key: KeyPath<NextDayOutcome, Double?>) -> [(minutes: Double, value: Double)] {
            nights.compactMap { n in n.outcome[keyPath: key].map { (Double(n.asleepMinutes), $0) } }
        }

        // Free nights are picked as weekends, which tend to run long, so the
        // rebound leans high: its weight grows with samples (full at 12) and
        // tops out below the best knee fits.
        if let r = reboundEstimate(nights) {
            methods.append(.init(kind: .rebound, minutes: r.minutes, weight: 0.7 * min(Double(r.samples) / 12, 1), samples: r.samples))
        }
        add(.hrv, fitKnee(points(\.hrvDeltaPct), higherIsBetter: true), weight: 0.9)
        add(.restingHR, fitKnee(points(\.restingHRDelta), higherIsBetter: false), weight: 0.8)
        add(.energy, fitKnee(points(\.energyScore), higherIsBetter: true), weight: 0.6)
        add(.reaction, fitKnee(points(\.reactionSlowdownPct), higherIsBetter: false), weight: 0.7)
        add(.checkIn, fitKnee(points(\.checkIn), higherIsBetter: true), weight: 0.15)

        // Blend in the population prior; its pull fades as nights accumulate.
        let n = nights.count
        let priorWeight = 14.0 / Double(n + 14) * 2
        methods.append(.init(kind: .prior, minutes: populationPrior, weight: priorWeight, samples: 0))

        let totalW = methods.map(\.weight).reduce(0, +)
        let mean = methods.map { Double($0.minutes) * $0.weight }.reduce(0, +) / totalW
        let objective = methods.filter { $0.kind != .prior && $0.kind != .checkIn }
        let spread = objective.count >= 2
            ? (objective.map { Double($0.minutes) }.standardDeviation ?? 0)
            : 45
        let clamped = min(max(Int(mean.rounded()) + userAdjustment, researchLimits.lowerBound), researchLimits.upperBound)
        let half = Int(max(15, min(spread, 60)).rounded())

        // Confidence needs at least one strong knee fit; the rebound alone
        // never makes it "Fairly sure".
        let strong = objective.filter(\.isStrong)
        let confidence: SleepNeedEstimate.Confidence
        if n >= 56 && strong.count >= 2 && spread <= 25 { confidence = .good }
        else if n >= strongFitNights && !strong.isEmpty { confidence = .fair }
        else { confidence = .learning }

        return SleepNeedEstimate(minutes: clamped, range: TimeRange(clamped - half, clamped + half),
                                 confidence: confidence, nights: n, methods: methods)
    }
}

/// Sleep debt over the last 14 nights: the sum of each night's shortfall
/// against the need, gently weighted toward recent nights. The weights
/// average 1 per night, so 14 nights each 10 minutes short is 140 minutes
/// whatever the weighting, and 3 tracked nights sum 3 shortfalls (no scaling
/// up to 14). Last night counts about 1.4×, the oldest about 0.7×. Surplus
/// nights pay debt back, at most 60 minutes a night.
public enum SleepDebt {
    public static let decay = 0.95

    public static func weights(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let raw = (0..<count).map { pow(decay, Double($0)) }
        let sum = raw.reduce(0, +)
        return raw.map { $0 / sum * Double(count) }
    }

    public static func minutes(need: Int, lastNightsNewestFirst asleep: [Int]) -> Int {
        let nights = Array(asleep.prefix(14))
        guard !nights.isEmpty else { return 0 }
        let w = weights(count: nights.count)
        let total = zip(nights, w).map { slept, wi in wi * Double(max(need - slept, -60)) }.reduce(0, +)
        return max(0, Int(total.rounded()))
    }
}

/// Tonight's need = base need + debt payback + adjustments − naps
/// (the same shape WHOOP documents: baseline, debt, strain, naps).
public struct TonightNeed: Hashable, Sendable {
    public struct Part: Hashable, Sendable { public var label: String; public var minutes: Int }
    public var total: Int
    public var parts: [Part]

    public init(base: Int, debt: Int, lateLuteal: Bool = false, effortAboveTarget: Double = 0, unwell: Bool = false, napMinutes: Int = 0) {
        var parts = [Part(label: "Your base need", minutes: base)]
        let payback = min(Int((Double(debt) * 0.1 / 5).rounded()) * 5, 45)
        if payback > 0 { parts.append(.init(label: "Paying back sleep debt", minutes: payback)) }
        if lateLuteal { parts.append(.init(label: "Late luteal phase", minutes: 10)) }
        let effort = Int((max(0, effortAboveTarget) * 5).rounded())
        if effort > 0 { parts.append(.init(label: "Hard day", minutes: min(effort, 30))) }
        if unwell { parts.append(.init(label: "Fighting something off", minutes: 30)) }
        if napMinutes > 0 { parts.append(.init(label: "Naps", minutes: -min(napMinutes, 60))) }
        self.parts = parts
        self.total = parts.map(\.minutes).reduce(0, +)
    }
}

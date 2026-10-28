import Foundation

// MARK: - Tonight's plan

/// Tonight in one place: how much sleep she needs (base need plus debt
/// payback and adjustments), the bedtime and up-by she set, and what the wake
/// planner made of them. Every screen that quotes "tonight" (Today, Sleep,
/// the sick check, "Why do I feel off?", Settings, the Watch) reads these
/// numbers, so they can't disagree (Sam N3).
///
/// Three wake times, each with its own name:
/// - **best wake** (`wake`): the end of the last sleep cycle when it falls in
///   the 25 minutes before up-by, else up-by itself,
/// - **smart alarm window** (`alarmWindow`): the Watch listens for stirring
///   for 25 minutes: from 22 minutes before a cycle end to 3 after it, or
///   the 25 minutes up to up-by,
/// - **up by** (`upBy`): the latest she said she can get up. The window
///   never ends after it.
public struct TonightPlan: Hashable, Sendable {
    /// Tonight's need, minutes of sleep.
    public var need: Int
    /// Her base need (without payback or adjustments).
    public var baseNeed: Int
    /// The debt payback part of tonight's need (0 when there's none).
    public var payback: Int
    public var bedtime: Minutes
    public var upBy: Minutes
    /// Minutes to fall asleep after getting into bed.
    public var latency: Int
    /// Clock change during the night (−60 falling back, +60 springing forward).
    public var clockShift: Int
    /// The planner's result; nil when no whole sleep cycle fits.
    public var plan: WakePlan?

    public init(need: TonightNeed, bedtime: Minutes, upBy: Minutes, latency: Int = 12, clockShift: Int = 0, plan: WakePlan?) {
        self.need = need.total
        self.baseNeed = need.parts.first?.minutes ?? need.total
        self.payback = need.parts.first { $0.label == "Paying back sleep debt" }?.minutes ?? 0
        self.bedtime = bedtime
        self.upBy = upBy
        self.latency = latency
        self.clockShift = clockShift
        self.plan = plan
    }

    /// The best wake time (nil when no whole sleep cycle fits).
    public var wake: Minutes? { plan?.wake }
    public var alarmWindow: TimeRange? { plan?.alarmWindow }

    /// Real minutes between bedtime and up-by (an hour more the night the
    /// clocks fall back).
    public var timeInBedAllowed: Int { upBy - bedtime - clockShift }

    /// The most sleep bedtime → up-by allows, after falling asleep.
    public var mostSleepAllowed: Int { max(timeInBedAllowed - latency, 0) }

    /// Bedtime and up-by leave less time than tonight's need, before the
    /// plan even rounds to whole cycles. Say so plainly.
    public var bedtimeTooLateForNeed: Bool { mostSleepAllowed < need }

    /// Sleep the plan expects: from falling asleep to the best wake time
    /// (the most the window allows when no cycle fits).
    public var expectedAsleep: Int { plan?.asleep ?? mostSleepAllowed }

    /// Minutes short of tonight's need (0 when covered).
    public var shortfall: Int { max(need - expectedAsleep, 0) }

    /// Within 10 minutes counts as covering it (the planner's rule).
    public var coversNeed: Bool { shortfall <= 10 }

    /// The bedtime that would cover tonight's need before up-by, rounded
    /// down to 5 minutes (earlier is the safe side). Nil when tonight's plan
    /// already covers it.
    public var bedtimeToCoverNeed: Minutes? {
        guard !coversNeed else { return nil }
        if let b = plan?.bedtimeToCoverNeed { return Self.roundDown5(b) }
        return Self.roundDown5(upBy - clockShift - need - latency)
    }

    static func roundDown5(_ m: Minutes) -> Minutes { Int((Double(m) / 5).rounded(.down)) * 5 }
}

// MARK: - A night's stage timeline

public enum StageLayout {
    /// Stage totals from segments: what each stage tile and the chart's
    /// spoken summary show.
    public static func totals(_ segments: [StageSegment]) -> [SleepStage: Int] {
        var out: [SleepStage: Int] = [:]
        for s in segments { out[s.stage, default: 0] += s.minutes }
        return out
    }

    /// A typical night's order of stages (deep sleep early, REM growing toward
    /// morning), laid out from `onset` in whole minutes so each stage adds up
    /// to exactly `stageMinutes[stage]`. The timeline then ends at onset +
    /// asleep + awake, matching the "fell asleep" and "woke up" times (Sam N1).
    public static func typical(onset: Date, stageMinutes: [SleepStage: Int]) -> [StageSegment] {
        let template: [(SleepStage, Double)] = [
            (.core, 12), (.deep, 30), (.core, 14), (.rem, 8),
            (.core, 22), (.deep, 22), (.core, 12), (.rem, 14),
            (.core, 26), (.deep, 12), (.awake, 4), (.core, 14), (.rem, 20),
            (.core, 30), (.deep, 6), (.rem, 26), (.awake, 6),
            (.core, 32), (.rem, 34), (.awake, 4), (.core, 12),
        ]
        // Split each stage's total across its template slots in whole
        // minutes (largest remainder), so the per-stage sums are exact.
        var lengths = Array(repeating: 0, count: template.count)
        for stage in SleepStage.allCases {
            let target = max(stageMinutes[stage] ?? 0, 0)
            let slots = template.indices.filter { template[$0].0 == stage }
            let weight = slots.map { template[$0].1 }.reduce(0, +)
            guard target > 0, weight > 0 else { continue }
            let exact = slots.map { template[$0].1 / weight * Double(target) }
            var given = exact.map { Int($0.rounded(.down)) }
            var left = target - given.reduce(0, +)
            let order = exact.indices.sorted { (exact[$0] - Double(given[$0])) > (exact[$1] - Double(given[$1])) }
            for i in order where left > 0 { given[i] += 1; left -= 1 }
            for (k, slot) in slots.enumerated() { lengths[slot] = given[k] }
        }
        var t = onset
        var out: [StageSegment] = []
        for (i, (stage, _)) in template.enumerated() where lengths[i] > 0 {
            let end = t.addingTimeInterval(TimeInterval(lengths[i] * 60))
            out.append(StageSegment(stage: stage, start: t, end: end))
            t = end
        }
        return out
    }
}

// MARK: - Energy curve, relative cue

public extension EnergyDay {
    /// The highest point of the whole curve: the one peak the Energy
    /// summary, the chart's dot and the readout's "below today's peak" all
    /// use (F2). `highest` is the first peak, which an evening second wind
    /// can top.
    var dayPeak: Point { curve.max { $0.level < $1.level } ?? highest }

    /// Where a level sits within today's own range, so a narrow day (53 to
    /// 59) doesn't read flat while scrubbing (Priya U7): "today's peak",
    /// "near today's peak", "3 below today's peak", "near today's low",
    /// "today's low". Uses whole points, as shown on screen.
    func relativeCue(level: Double) -> String {
        let levels = curve.map { Int($0.level.rounded()) }
        guard let lo = levels.min() else { return "" }
        let hi = Int(dayPeak.level.rounded())
        let l = Int(level.rounded())
        if l >= hi { return "today's peak" }
        if hi - l <= 1 { return "near today's peak" }
        if l <= lo { return "today's low" }
        if l - lo <= 1 { return "near today's low" }
        return "\(hi - l) below today's peak"
    }
}

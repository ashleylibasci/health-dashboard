import Foundation

/// One morning: when she woke, what stage she woke from, and how it went.
public struct Morning: Hashable, Codable, Sendable {
    public var wake: Minutes
    public var wokeFromLightSleep: Bool?
    /// Any outcome on a consistent scale: check-in (1–5), energy or recovery.
    public var outcome: Double
    public init(wake: Minutes, wokeFromLightSleep: Bool?, outcome: Double) {
        self.wake = wake; self.wokeFromLightSleep = wokeFromLightSleep; self.outcome = outcome
    }
}

/// What past wake-ups say about when to wake.
public struct WakeHistory: Hashable, Sendable {
    public struct Bucket: Hashable, Sendable {
        public var range: TimeRange
        public var mean: Double
        public var count: Int
    }
    public var buckets: [Bucket]
    /// The 40-minute window with the best average outcome.
    public var bestWindow: TimeRange?
    public var bestWindowMean: Double?
    public var bestWindowCount: Int
    /// How much better light-sleep wake-ups went than deep/REM ones.
    public var lightSleepAdvantage: Double?

    public static let defaultEdges: [Minutes] = [0, 420, 470, 510, 570, 1440]

    public static func analyze(_ mornings: [Morning], edges: [Minutes] = defaultEdges, windowWidth: Int = 40) -> WakeHistory {
        let buckets: [Bucket] = zip(edges, edges.dropFirst()).compactMap { lo, hi in
            let xs = mornings.filter { $0.wake >= lo && $0.wake < hi }.map(\.outcome)
            guard let m = xs.mean else { return nil }
            return Bucket(range: TimeRange(lo, hi), mean: m, count: xs.count)
        }

        let minCount = max(5, mornings.count / 10)
        var best: (TimeRange, Double, Int)?
        for start in stride(from: 300, through: 660, by: 10) {
            let xs = mornings.filter { $0.wake >= start && $0.wake < start + windowWidth }.map(\.outcome)
            guard xs.count >= minCount, let m = xs.mean else { continue }
            if best == nil || m > best!.1 { best = (TimeRange(start, start + windowWidth), m, xs.count) }
        }
        // Picking the best of ~35 overlapping windows finds one that looks
        // better by chance (Liu 10). It only counts when its mornings beat
        // the rest by at least half of her usual morning-to-morning spread,
        // and by a margin well past chance for the number of mornings (2.5
        // standard errors, stricter than usual because many windows were
        // tried).
        if let b = best {
            let inside = mornings.filter { $0.wake >= b.0.start && $0.wake < b.0.end }.map(\.outcome)
            let outside = mornings.filter { $0.wake < b.0.start || $0.wake >= b.0.end }.map(\.outcome)
            let spread = mornings.map(\.outcome).standardDeviation ?? 0
            let diff = (inside.mean ?? 0) - (outside.mean ?? 0)
            let standardError = spread * (1 / Double(max(inside.count, 1)) + 1 / Double(max(outside.count, 1))).squareRoot()
            if outside.count < minCount || spread <= 0 || diff < 0.5 * spread || diff < 2.5 * standardError {
                best = nil
            }
        }

        let light = mornings.filter { $0.wokeFromLightSleep == true }.map(\.outcome)
        let deep = mornings.filter { $0.wokeFromLightSleep == false }.map(\.outcome)
        let advantage = (light.mean != nil && deep.mean != nil && light.count >= 3 && deep.count >= 3) ? light.mean! - deep.mean! : nil

        return WakeHistory(buckets: buckets, bestWindow: best?.0, bestWindowMean: best?.1,
                           bestWindowCount: best?.2 ?? 0, lightSleepAdvantage: advantage)
    }
}

/// Picks tomorrow's wake time and smart-alarm window.
///
/// She sleeps until her up-by time unless the end of a sleep cycle falls in
/// the last `maxCycleTrade` minutes before it: then she wakes at that cycle
/// end instead. Waking near the end of a cycle can feel a little easier, but
/// it is never worth more than about 25 minutes of sleep (Park 1).
public struct WakePlan: Hashable, Sendable {
    public struct Reason: Hashable, Sendable {
        public enum Kind: String, Sendable { case cycleEnd, bestWindow, sleepNeed }
        public var kind: Kind
        public var ok: Bool
        public var title: String
        public var detail: String
    }

    public var wake: Minutes
    public var alarmWindow: TimeRange
    /// Whole sleep cycles before the wake time.
    public var cycles: Int
    public var asleep: Int
    /// Positive when short of tonight's need.
    public var shortfall: Int
    public var reasons: [Reason]
    /// Latest bedtime that covers the need before up-by, if tonight's doesn't.
    public var bedtimeToCoverNeed: Minutes?
    /// How far into a cycle the current alarm lands, when one is set.
    public var currentAlarmMinutesIntoCycle: Int?
    /// True when the wake time is the end of a sleep cycle; false when it's
    /// the up-by time itself (no cycle ends close enough before it).
    public var endsCycle: Bool = true
}

public enum WakePlanner {
    /// The most sleep given up to wake at the end of a cycle instead of at up-by.
    public static let maxCycleTrade = 25

    public struct Input: Sendable {
        public var bedtime: Minutes
        public var latency: Int
        public var cycleLength: Int
        public var deadline: Minutes
        public var tonightNeed: Int
        public var bestWindow: TimeRange?
        public var currentAlarmLatest: Minutes?
        public var windowLength: Int
        /// How far the clocks jump during the night: −60 when they fall back
        /// (an extra hour in bed), +60 when they spring forward. Bedtime is
        /// on the clock before the change; deadline, wake and window on the
        /// clock after it.
        public var clockShift: Int

        public init(bedtime: Minutes, latency: Int = 12, cycleLength: Int = 92, deadline: Minutes, tonightNeed: Int, bestWindow: TimeRange? = nil, currentAlarmLatest: Minutes? = nil, windowLength: Int = 30, clockShift: Int = 0) {
            self.bedtime = bedtime; self.latency = latency; self.cycleLength = cycleLength; self.deadline = deadline
            self.tonightNeed = tonightNeed; self.bestWindow = bestWindow; self.currentAlarmLatest = currentAlarmLatest; self.windowLength = windowLength
            self.clockShift = clockShift
        }
    }

    public static func plan(_ input: Input) -> WakePlan? {
        guard input.clockShift == 0 else { return planAcrossClockChange(input) }
        let onset = input.bedtime + input.latency
        let maxCycles = (input.deadline - onset) / input.cycleLength
        guard maxCycles >= 1 else { return nil }

        // The last cycle end before up-by, used only when it costs at most
        // 25 minutes of sleep, and never when it would make a night that
        // covers the need at up-by fall short of it.
        let cycleEnd = onset + maxCycles * input.cycleLength
        let coversAtUpBy = input.deadline - onset >= input.tonightNeed - 10
        let coversAtCycle = maxCycles * input.cycleLength >= input.tonightNeed - 10
        let endsCycle = input.deadline - cycleEnd <= maxCycleTrade && (coversAtCycle || !coversAtUpBy)

        let wake = endsCycle ? cycleEnd : input.deadline
        let asleep = wake - onset
        let n = asleep / input.cycleLength
        let shortfall = max(0, input.tonightNeed - asleep)
        // The Watch listens for `windowLength + 3` minutes: from
        // `windowLength` before a cycle end to 3 after it, or up to up-by.
        // It never runs past up-by, and keeps its full length when a cycle
        // ends right at up-by.
        let windowEnd = endsCycle ? min(wake + 3, input.deadline) : wake
        let window = TimeRange(windowEnd - input.windowLength - 3, windowEnd)

        var reasons: [WakePlan.Reason] = []
        if endsCycle {
            reasons.append(.init(kind: .cycleEnd, ok: true, title: "Near the end of a sleep cycle",
                                 detail: "Cycle \(n) ends around \(Clock.format(wake)), \(input.deadline - wake) minutes before your up-by time. Waking near the end of a cycle can feel a bit easier. Cycle timing varies, so this is a rough guide."))
        } else {
            reasons.append(.init(kind: .cycleEnd, ok: true, title: "All the sleep your up-by time allows",
                                 detail: "No sleep cycle ends close enough before \(Clock.format(wake)), so you sleep until your up-by time. Waking earlier just to finish a cycle would cost more sleep than it's worth."))
        }
        if let w = input.bestWindow {
            let inside = w.contains(wake)
            reasons.append(.init(kind: .bestWindow, ok: inside,
                                 title: inside ? "Inside your best wake window" : "Outside your best wake window",
                                 detail: "You've felt best waking \(w.label)."))
        }
        let covers = shortfall <= 10
        reasons.append(.init(kind: .sleepNeed, ok: covers,
                             title: covers ? "Covers tonight's sleep need" : "\(Clock.duration(shortfall)) short of tonight's need",
                             detail: "\(Clock.duration(asleep)) of the \(Clock.duration(input.tonightNeed)) you need tonight." + (covers ? "" : " The rest goes onto your sleep debt.")))

        // The latest bedtime that leaves the whole need before up-by, rounded
        // down to 5 minutes: "bed by 11:05pm", not 11:06pm. At that bedtime
        // the plan covers the need whether it wakes at up-by or a cycle end.
        let bedForNeed = Int((Double(input.deadline - input.tonightNeed - input.latency) / 5).rounded(.down)) * 5
        let into = input.currentAlarmLatest.map { (($0 - onset) % input.cycleLength + input.cycleLength) % input.cycleLength }

        return WakePlan(wake: wake, alarmWindow: window, cycles: n, asleep: asleep, shortfall: shortfall,
                        reasons: reasons, bedtimeToCoverNeed: shortfall > 10 ? bedForNeed : nil,
                        currentAlarmMinutesIntoCycle: into, endsCycle: endsCycle)
    }

    /// A night with a clock change: plan on elapsed time (the clock after
    /// the change, moved back by the shift), then put the morning's times
    /// back on the new clock. Bedtimes stay on the old clock.
    static func planAcrossClockChange(_ input: Input) -> WakePlan? {
        let shift = input.clockShift
        var elapsed = input
        elapsed.clockShift = 0
        elapsed.deadline = input.deadline - shift
        elapsed.bestWindow = input.bestWindow.map { TimeRange($0.start - shift, $0.end - shift) }
        elapsed.currentAlarmLatest = input.currentAlarmLatest.map { $0 - shift }
        guard let p = plan(elapsed) else { return nil }
        let wake = p.wake + shift
        let window = TimeRange(p.alarmWindow.start + shift, p.alarmWindow.end + shift)
        let reasons = p.reasons.map { r -> WakePlan.Reason in
            var r = r
            if r.kind == .cycleEnd {
                r.detail = p.endsCycle
                    ? "Cycle \(p.cycles) ends around \(Clock.format(wake)) on the new clock. Waking near the end of a cycle can feel a bit easier. Cycle timing varies, so this is a rough guide."
                    : "No sleep cycle ends close enough before \(Clock.format(wake)) on the new clock, so you sleep until your up-by time."
            }
            return r
        }
        return WakePlan(wake: wake, alarmWindow: window, cycles: p.cycles, asleep: p.asleep, shortfall: p.shortfall,
                        reasons: reasons, bedtimeToCoverNeed: p.bedtimeToCoverNeed,
                        currentAlarmMinutesIntoCycle: p.currentAlarmMinutesIntoCycle, endsCycle: p.endsCycle)
    }

    /// Her typical cycle length from tracked nights: total asleep time divided
    /// by the number of REM bouts (each cycle ends in REM). Falls back to 92.
    public static func cycleLength(from sessions: [SleepSession]) -> Int {
        let estimates: [Double] = sessions.compactMap { s in
            var bouts = 0
            var lastWasREM = false
            for seg in s.segments where seg.stage != .awake {
                if seg.stage == .rem && !lastWasREM { bouts += 1 }
                lastWasREM = seg.stage == .rem
            }
            guard bouts >= 3 else { return nil }
            return Double(s.asleepMinutes) / Double(bouts)
        }
        guard estimates.count >= 5, let m = estimates.median else { return 92 }
        return min(max(Int(m.rounded()), 80), 110)
    }
}

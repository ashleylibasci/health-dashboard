import Foundation

/// Predicts the day's energy curve with the two-process model of sleep
/// regulation (Borbély): a homeostatic pressure that builds while awake and
/// drains during sleep, plus a circadian rhythm timed from her body clock.
/// Fatigue tools like SAFTE, and apps like RISE, build on the same idea.
public struct EnergyDay: Hashable, Sendable {
    public struct Point: Hashable, Sendable { public var time: Minutes; public var level: Double }
    public struct Zone: Hashable, Sendable {
        public enum Kind: String, Sendable, CaseIterable { case grogginess, morningPeak, afternoonDip, secondWind, windDown, melatonin }
        public var kind: Kind
        public var range: TimeRange
        /// Zone names that match the clock. After a late wake the first peak
        /// can fall in the afternoon, so it isn't called a "morning" peak, and
        /// a dip outside the afternoon isn't an "afternoon" dip.
        public var title: String {
            switch kind {
            case .grogginess: return "Grogginess"
            case .morningPeak: return range.start >= 720 ? "First peak" : "Morning peak"
            case .afternoonDip: return (720..<1080).contains(range.start) ? "Afternoon dip" : "Energy dip"
            case .secondWind: return "Second wind"
            case .windDown: return "Wind-down"
            case .melatonin: return "Melatonin"
            }
        }
    }

    public var curve: [Point]
    public var zones: [Zone]
    /// 0–100, the average predicted alertness over a fixed 16 hours from
    /// waking, so days with different wake times and bedtimes compare fairly.
    public var score: Int
    public var highest: Point
    public var lowest: Point
    /// What the day was computed from.
    public var input: EnergyModel.Input

    public func zone(_ kind: Zone.Kind) -> Zone? { zones.first { $0.kind == kind } }
    public func level(at t: Minutes) -> Double? {
        guard let i = curve.firstIndex(where: { $0.time >= t }) else { return curve.last?.level }
        return curve[i].level
    }
}

public enum EnergyModel {
    public struct Input: Hashable, Sendable {
        /// When she woke (minutes after midnight).
        public var wake: Minutes
        public var asleepMinutes: Int
        public var sleepDebt: Int
        /// Habitual mid-sleep (MCTQ-style), minutes after midnight. Sets circadian timing.
        public var habitualMidSleep: Minutes
        /// Habitual sleep onset on work nights, for the melatonin window. May exceed 1440.
        public var habitualSleepOnset: Minutes
        public var wokeFromLightSleep: Bool
        /// Planned bedtime tonight (may exceed 1440).
        public var bedtime: Minutes
        /// Her sleep need. Sleep beyond it doesn't add energy (the benefit
        /// plateaus at the need). Nil: no cap.
        public var sleepNeed: Int?

        public init(wake: Minutes, asleepMinutes: Int, sleepDebt: Int, habitualMidSleep: Minutes, habitualSleepOnset: Minutes, wokeFromLightSleep: Bool = true, bedtime: Minutes, sleepNeed: Int? = nil) {
            self.wake = wake; self.asleepMinutes = asleepMinutes; self.sleepDebt = sleepDebt
            self.habitualMidSleep = habitualMidSleep; self.habitualSleepOnset = habitualSleepOnset
            self.wokeFromLightSleep = wokeFromLightSleep; self.bedtime = bedtime; self.sleepNeed = sleepNeed
        }
    }

    // Process S time constants (hours), from the published model.
    static let tauRise = 18.2, tauFall = 4.2

    public static func day(_ input: Input, step: Int = 10) -> EnergyDay {
        // Homeostatic pressure at wake: assume a 16h day before bed, then decay
        // over the sleep period. Debt adds residual pressure.
        let sBed = 1 - (1 - 0.15) * exp(-16 / tauRise)
        let restorative = input.sleepNeed.map { min(input.asleepMinutes, $0) } ?? input.asleepMinutes
        let sWake0 = sBed * exp(-Double(restorative) / 60 / tauFall)
        let sWake = min(sWake0 + Double(input.sleepDebt) / 60 * 0.035, 0.9)
        let debtDamping = max(0.55, 1 - Double(input.sleepDebt) / 60 * 0.06)

        // Circadian phase from mid-sleep: the 24h component peaks ~14h after
        // mid-sleep (the evening "second wind"), the 12h component gives the
        // late-morning peak and the post-lunch dip. Tuned so a 4:22am
        // mid-sleep peaks near 11:30am and dips near 4pm.
        let mid = Double(input.habitualMidSleep) / 60
        let phi24 = mid + 14.0, phi12 = mid + 6.0
        let inertiaK = input.wokeFromLightSleep ? 0.22 : 0.4
        let inertiaTau = input.wokeFromLightSleep ? 25.0 : 45.0

        func circadian(_ t: Minutes) -> Double {
            let h = Double(t) / 60
            return 0.30 * cos(2 * .pi * (h - phi24) / 24) + 0.12 * cos(2 * .pi * (h - phi12) / 12)
        }
        func rescale(_ raw: Double) -> Double { min(max((raw - 0.05) / 0.85 * 100, 0), 100) }

        var curve: [EnergyDay.Point] = []
        var scored: [Double] = []
        let end = max(input.bedtime + 90, input.wake + 17 * 60)
        // The score covers a fixed 16 hours awake from wake, so days with
        // different wake times and bedtimes compare fairly (a later wake
        // doesn't skip the tired evening hours). Past an hour after her usual
        // sleep onset the body-clock part is held at its value then: a late
        // waker isn't marked down for the middle of a night she'd normally
        // sleep through, only for the extra hours awake.
        let scoredEnd = input.wake + scoredHours * 60
        let clockHold = max(input.habitualSleepOnset + 60, input.wake)
        for t in stride(from: input.wake, through: end, by: step) {
            let awakeH = Double(t - input.wake) / 60
            let s = 1 - (1 - sWake) * exp(-awakeH / tauRise)
            let inertia = inertiaK * exp(-Double(t - input.wake) / inertiaTau)
            let raw = (1 - s) + circadian(t) * debtDamping - inertia
            curve.append(.init(time: t, level: rescale(raw)))
            if t <= scoredEnd {
                scored.append(rescale((1 - s) + circadian(min(t, clockHold)) * debtDamping - inertia))
            }
        }
        let score = Int(((scored.mean ?? 50)).rounded())

        // Zones.
        var zones: [EnergyDay.Zone] = []
        let groggyEnd = curve.first(where: { inertiaK * exp(-Double($0.time - input.wake) / inertiaTau) < 0.04 })?.time
        if let groggyEnd {
            zones.append(.init(kind: .grogginess, range: TimeRange(input.wake, groggyEnd)))
        }
        let daytime = curve.filter { $0.time > input.wake + 90 && $0.time < input.bedtime - 60 }
        func extremum(in lo: Minutes, _ hi: Minutes, max isMax: Bool) -> EnergyDay.Point? {
            let pts = daytime.filter { $0.time >= lo && $0.time <= hi }
            return isMax ? pts.max { $0.level < $1.level } : pts.min { $0.level < $1.level }
        }
        // A band never crosses halfway to the neighbouring extremum, so zones
        // stay in order and never overlap, even on a flat late-wake curve.
        func band(around p: EnergyDay.Point, within delta: Double, isMax: Bool, after lo: Minutes = .min, before hi: Minutes = .max) -> TimeRange {
            let i = curve.firstIndex(of: p)!
            var a = i, b = i
            while a > 0, curve[a - 1].time > lo, abs(curve[a - 1].level - p.level) <= delta, (isMax ? curve[a - 1].level <= p.level : curve[a - 1].level >= p.level) { a -= 1 }
            while b < curve.count - 1, curve[b + 1].time < hi, abs(curve[b + 1].level - p.level) <= delta, (isMax ? curve[b + 1].level <= p.level : curve[b + 1].level >= p.level) { b += 1 }
            return TimeRange(curve[a].time, curve[b].time)
        }
        func halfway(_ x: EnergyDay.Point?, _ y: EnergyDay.Point?) -> Minutes? {
            guard let x, let y else { return nil }
            return (x.time + y.time) / 2
        }
        let peak1 = extremum(in: input.wake + 90, input.wake + 7 * 60, max: true)
        let dip = peak1.flatMap { extremum(in: $0.time + 60, $0.time + 6 * 60, max: false) }
        let peak2 = dip.flatMap { extremum(in: $0.time + 60, input.bedtime - 120, max: true) }
        let m1 = halfway(peak1, dip), m2 = halfway(dip, peak2)
        if let p = peak1 { zones.append(.init(kind: .morningPeak, range: band(around: p, within: 3, isMax: true, after: groggyEnd ?? .min, before: m1 ?? .max))) }
        if let d = dip { zones.append(.init(kind: .afternoonDip, range: band(around: d, within: 3, isMax: false, after: m1 ?? .min, before: m2 ?? .max))) }
        if let p = peak2 { zones.append(.init(kind: .secondWind, range: band(around: p, within: 3, isMax: true, after: m2 ?? .min))) }

        // Melatonin rises in the hour before her habitual sleep onset.
        let melStart = input.habitualSleepOnset - 57
        zones.append(.init(kind: .windDown, range: TimeRange(melStart - 15, melStart)))
        zones.append(.init(kind: .melatonin, range: TimeRange(melStart, melStart + 60)))

        let highest = (peak1 ?? curve.max { $0.level < $1.level })!
        let lowest = (dip ?? curve.min { $0.level < $1.level })!
        return EnergyDay(curve: curve, zones: zones, score: score, highest: highest, lowest: lowest, input: input)
    }

    /// Hours after waking that the score averages over.
    public static let scoredHours = 16

    /// One input to the model and how many score points it moved today:
    /// the score as it is minus the score with that input at a neutral
    /// value (slept exactly her need, no debt, woke from light sleep, woke at
    /// her body clock's usual time). Interactions mean they don't add up to
    /// the whole score exactly.
    public struct Driver: Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable { case lastNight, sleepDebt, wokeFromDeepSleep, wakeTime }
        public var kind: Kind
        public var points: Int
        /// The value that was compared against the neutral one: minutes asleep,
        /// minutes of debt, or minutes later (+) / earlier (−) than the body clock's wake.
        public var amount: Int
    }

    /// The model's own drivers for `input`, biggest effect first. `need` is her
    /// sleep need in minutes. Drivers with no effect are left out.
    public static func drivers(_ input: Input, need: Int) -> [Driver] {
        let actual = day(input).score
        func moved(_ change: (inout Input) -> Void) -> Int {
            var alt = input
            change(&alt)
            return actual - day(alt).score
        }
        var out: [Driver] = []
        out.append(Driver(kind: .lastNight, points: moved { $0.asleepMinutes = need }, amount: input.asleepMinutes))
        if input.sleepDebt > 0 {
            out.append(Driver(kind: .sleepDebt, points: moved { $0.sleepDebt = 0 }, amount: input.sleepDebt))
        }
        if !input.wokeFromLightSleep {
            out.append(Driver(kind: .wokeFromDeepSleep, points: moved { $0.wokeFromLightSleep = true }, amount: 0))
        }
        // Her body clock's usual wake: habitual mid-sleep plus half her need.
        let clockWake = input.habitualMidSleep + need / 2
        let offset = input.wake - clockWake
        if abs(offset) >= 30 {
            out.append(Driver(kind: .wakeTime, points: moved { $0.wake = clockWake }, amount: offset))
        }
        return out.filter { $0.points != 0 }.sorted { abs($0.points) > abs($1.points) }
    }
}

/// A body-battery style bank: charges while asleep, drains while awake.
public enum EnergyBank {
    public static func atWake(asleepMinutes: Int, sleepDebt: Int, hrvDeltaPct: Double) -> Double {
        min(max(30 + Double(asleepMinutes) / 60 * 7 - Double(sleepDebt) / 60 * 4 + hrvDeltaPct * 0.5, 5), 100)
    }
    /// Always 0–100, whatever the inputs (a time before wake doesn't add charge).
    public static func level(atWake start: Double, hoursAwake: Double, stressLoad: Double = 0) -> Double {
        min(max(start - max(hoursAwake, 0) * (2.9 + stressLoad), 0), 100)
    }
}

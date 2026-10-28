import Foundation

public enum SleepStage: String, Codable, Sendable, CaseIterable {
    case awake, rem, core, deep
    /// Stages a smart alarm treats as easy to wake from.
    public var isLight: Bool { self == .core || self == .awake }
}

public struct StageSegment: Hashable, Codable, Sendable {
    public var stage: SleepStage
    public var start: Date
    public var end: Date
    public init(stage: SleepStage, start: Date, end: Date) {
        self.stage = stage; self.start = start; self.end = end
    }
    public var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
}

/// One night of sleep, built from Apple Health sleep-analysis samples.
public struct SleepSession: Hashable, Codable, Sendable {
    public var inBed: Date
    public var wake: Date
    public var segments: [StageSegment]
    /// True when no alarm was set for that morning (a "free" night).
    public var alarmUsed: Bool

    public init(inBed: Date, wake: Date, segments: [StageSegment], alarmUsed: Bool = true) {
        self.inBed = inBed; self.wake = wake; self.segments = segments.sorted { $0.start < $1.start }; self.alarmUsed = alarmUsed
    }

    public var sleepOnset: Date { segments.first { $0.stage != .awake }?.start ?? inBed }
    public var asleepMinutes: Int { segments.filter { $0.stage != .awake }.map(\.minutes).reduce(0, +) }
    public var latencyMinutes: Int { max(0, Int(sleepOnset.timeIntervalSince(inBed) / 60)) }
    public func minutes(in stage: SleepStage) -> Int { segments.filter { $0.stage == stage }.map(\.minutes).reduce(0, +) }
    /// Awake minutes between falling asleep and waking. Lying awake before
    /// sleep isn't counted, so fell-asleep → woke-up always covers asleep +
    /// awake (Sam N1).
    public var awakeAfterOnsetMinutes: Int {
        let onset = sleepOnset
        return segments.filter { $0.stage == .awake && $0.start >= onset }.map(\.minutes).reduce(0, +)
    }

    /// The stage she was in just before waking.
    public var wakeStage: SleepStage? { segments.last { $0.stage != .awake }?.stage }
    public var wokeFromLightSleep: Bool? { wakeStage.map { $0 == .core } }
}

/// What the body did the day after a night's sleep. Any field can be missing.
public struct NextDayOutcome: Hashable, Codable, Sendable {
    /// HRV vs the person's 30-day baseline, in percent.
    public var hrvDeltaPct: Double?
    /// Resting heart rate vs baseline, in bpm (higher is worse).
    public var restingHRDelta: Double?
    /// Morning check-in, 1–5.
    public var checkIn: Double?
    /// Reaction-test slowdown vs baseline, in percent (higher is worse).
    public var reactionSlowdownPct: Double?
    /// The day's energy score, 0–100.
    public var energyScore: Double?

    public init(hrvDeltaPct: Double? = nil, restingHRDelta: Double? = nil, checkIn: Double? = nil, reactionSlowdownPct: Double? = nil, energyScore: Double? = nil) {
        self.hrvDeltaPct = hrvDeltaPct; self.restingHRDelta = restingHRDelta; self.checkIn = checkIn
        self.reactionSlowdownPct = reactionSlowdownPct; self.energyScore = energyScore
    }
}

/// A night paired with how the next day went: the unit every model learns from.
public struct NightRecord: Hashable, Codable, Sendable {
    public var wakeDay: Date
    public var bedtime: Minutes
    public var sleepOnset: Minutes
    public var wake: Minutes
    public var asleepMinutes: Int
    public var alarmUsed: Bool
    public var wokeFromLightSleep: Bool?
    public var outcome: NextDayOutcome

    public init(wakeDay: Date, bedtime: Minutes, sleepOnset: Minutes, wake: Minutes, asleepMinutes: Int, alarmUsed: Bool = true, wokeFromLightSleep: Bool? = nil, outcome: NextDayOutcome = .init()) {
        self.wakeDay = wakeDay; self.bedtime = bedtime; self.sleepOnset = sleepOnset; self.wake = wake
        self.asleepMinutes = asleepMinutes; self.alarmUsed = alarmUsed; self.wokeFromLightSleep = wokeFromLightSleep; self.outcome = outcome
    }

    public init(session: SleepSession, outcome: NextDayOutcome, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: session.wake)
        self.init(
            wakeDay: day,
            bedtime: Clock.minutes(session.inBed, relativeTo: day, calendar: calendar),
            sleepOnset: Clock.minutes(session.sleepOnset, relativeTo: day, calendar: calendar),
            wake: Clock.minutes(session.wake, relativeTo: day, calendar: calendar),
            asleepMinutes: session.asleepMinutes,
            alarmUsed: session.alarmUsed,
            wokeFromLightSleep: session.wokeFromLightSleep,
            outcome: outcome)
    }
}

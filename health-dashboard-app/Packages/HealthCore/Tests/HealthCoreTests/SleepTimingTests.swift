import XCTest
@testable import HealthCore

/// Best bedtime and wake time (Park's method): the prior, the personal
/// evidence and its guards, and what it may and may not say.
final class SleepTimingTests: XCTestCase {

    // MARK: Test data

    /// A seeded normal generator, so every run is the same.
    struct Gen {
        var rng: SeededRandom
        init(seed: UInt64) { rng = SeededRandom(seed: seed) }
        mutating func normal() -> Double {
            let u = max(rng.next(), 1e-12), v = rng.next()
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        }
    }

    /// What one generated night looks like before it becomes a record.
    struct Draft {
        var index: Int
        var onset: Int
        /// How far from her usual onset, in standard deviations.
        var z: Double
        var asleep: Int
        var hrv: Double
        var rhr: Double
        var flags: SleepTiming.Flags = []
        var cycleShift: CycleHeartShift = .none
        var alarm = true
    }

    static let day0 = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 2))!
    static let need = 480, upBy = 480

    /// `n` consecutive nights around midnight (onset SD 60 min), asleep
    /// exactly her need, HRV noise 3% and resting heart rate noise 1 bpm.
    /// `shape` plants effects.
    static func makeNights(n: Int, seed: UInt64, onsetMean: Int = 0, onsetSD: Double = 60,
                           shape: (inout Draft, inout Gen) -> Void = { _, _ in }) -> [SleepTiming.Night] {
        var g = Gen(seed: seed)
        return (0..<n).map { i in
            let z = g.normal()
            var d = Draft(index: i, onset: onsetMean + Int((z * onsetSD).rounded()), z: z, asleep: need,
                          hrv: g.normal() * 3, rhr: g.normal())
            shape(&d, &g)
            let day = Calendar.current.date(byAdding: .day, value: i, to: day0)!
            let record = NightRecord(wakeDay: day, bedtime: d.onset - 12, sleepOnset: d.onset, wake: d.onset + d.asleep + 15,
                                     asleepMinutes: d.asleep, alarmUsed: d.alarm,
                                     outcome: NextDayOutcome(hrvDeltaPct: d.hrv, restingHRDelta: d.rhr))
            return SleepTiming.Night(record: record, flags: d.flags, cycleShift: d.cycleShift, wakeWeek: i / 7)
        }
    }

    /// Earliest third of a normal spread: z below −0.43.
    static func isEarly(_ d: Draft) -> Bool { d.z < -0.43 }

    /// HRV +10% and resting heart rate −2 bpm after the earliest third of nights.
    static func earlyIsBetter(_ d: inout Draft, _ g: inout Gen) {
        if isEarly(d) { d.hrv += 10; d.rhr -= 2 }
    }

    static func input(_ nights: [SleepTiming.Night], chronotype: Chronotype? = nil, free: Int = 0, work: Int = 0,
                      clockShift: Int = 0, tomorrowIsFree: Bool = false, upBy: Int = upBy) -> SleepTiming.Input {
        SleepTiming.Input(nights: nights, need: need, upBy: upBy, chronotype: chronotype, freeNights: free, workNights: work,
                          clockShift: clockShift, tomorrowIsFree: tomorrowIsFree)
    }

    static func recommend(_ nights: [SleepTiming.Night], clockShift: Int = 0) -> SleepTiming.Result {
        SleepTiming.recommend(input(nights, clockShift: clockShift))
    }

    /// A claim: a personal window that moved.
    static func claims(_ r: SleepTiming.Result) -> Bool { r.shift != 0 || r.evidence != nil }

    static func chronotype(msfsc: Minutes, jetlag: Int = 90) -> Chronotype {
        Chronotype(midSleepWork: msfsc - jetlag, midSleepFree: msfsc, midSleepFreeCorrected: msfsc, weeklyAverageSleep: 470,
                   socialJetlag: jetlag, category: Chronotype.category(for: msfsc))
    }

    // MARK: 1–5 The prior

    // 1. Ten nights: the prior only, from need and up-by.
    func testPriorOnlyWithFewNights() {
        let r = Self.recommend(Self.makeNights(n: 10, seed: 1))
        XCTAssertEqual(r.confidence, .learning)
        XCTAssertEqual(r.shift, 0)
        XCTAssertEqual(r.bed.end, SleepTiming.roundDown5(Self.upBy - Self.need - 12))
        XCTAssertEqual(r.bed.length, SleepTiming.windowWidth)
        XCTAssertEqual(r.basis, .needOnly)
        XCTAssertTrue(r.confidenceText.contains("(10 of 28)"), r.confidenceText)
    }

    // 2. Never later than the bedtime that covers her need.
    func testNeverLaterThanNeedBedtime() {
        var g = Gen(seed: 99)
        for k in 0..<300 {
            let need = 360 + Int(g.rng.next() * 240), upBy = 360 + Int(g.rng.next() * 240)
            let nights = Self.makeNights(n: Int(g.rng.next() * 70), seed: UInt64(k), onsetSD: 30 + g.rng.next() * 60) { d, gen in
                if gen.rng.next() < 0.5 { d.hrv += 8 }
            }
            let c = g.rng.next() < 0.5 ? Self.chronotype(msfsc: 120 + Int(g.rng.next() * 300)) : nil
            let r = SleepTiming.recommend(.init(nights: nights, need: need, upBy: upBy, chronotype: c, freeNights: 6, workNights: 10))
            let lat = SleepTiming.medianLatency(nights) ?? 12
            XCTAssertLessThanOrEqual(r.bed.end, SleepTiming.roundDown5(upBy - need - lat))
            XCTAssertLessThanOrEqual(r.wake.end, upBy)
        }
    }

    // 3. An early body clock sets the window: natural onset + 15.
    func testEarlyClockLeads() {
        // Mid-sleep 3:00am, need 8h: natural bed 11:00pm − 12 = 10:45pm.
        let c = Self.chronotype(msfsc: 180)
        let r = SleepTiming.recommend(Self.input(Self.makeNights(n: 5, seed: 2), chronotype: c, free: 4, work: 8))
        let natural = SleepTiming.roundDown5(180 - Self.need / 2 - 12)
        XCTAssertEqual(r.bed.end, natural + 15)
        XCTAssertEqual(r.basis, .needAndClock)
        XCTAssertNil(r.clockNote)
        XCTAssertTrue(r.why.contains("body clock"))
    }

    // 4. A late body clock: the need bedtime holds, and it's called a hard bedtime.
    func testLateClockIsAHardBedtime() {
        let c = Self.chronotype(msfsc: 360)   // 6am: onset about 2am
        let r = SleepTiming.recommend(Self.input(Self.makeNights(n: 5, seed: 3), chronotype: c, free: 5, work: 9))
        XCTAssertEqual(r.bed.end, SleepTiming.roundDown5(Self.upBy - Self.need - 12))
        XCTAssertEqual(r.basis, .needOnly)
        XCTAssertTrue(r.clockNote?.contains("hard bedtime") ?? false)
        XCTAssertTrue(r.clockNote?.contains("Morning light") ?? false, "a gap over 2 hours adds the note")
    }

    // 5. Three free nights: the body clock isn't used yet.
    func testThinChronotypeIgnored() {
        let c = Self.chronotype(msfsc: 180)
        let r = SleepTiming.recommend(Self.input(Self.makeNights(n: 5, seed: 4), chronotype: c, free: 3, work: 12))
        XCTAssertEqual(r.basis, .needOnly)
        XCTAssertEqual(r.bed.end, SleepTiming.roundDown5(Self.upBy - Self.need - 12))
    }

    // MARK: 6–9 Thresholds and confidence

    // 6. 27 eligible nights never count; 28 with a planted effect do.
    func testTwentyEightNightThreshold() {
        let nights = Self.makeNights(n: 28, seed: 1, shape: Self.earlyIsBetter)
        let below = Self.recommend(Array(nights.prefix(27)))
        XCTAssertEqual(below.confidence, .learning)
        XCTAssertEqual(below.shift, 0)
        let at = Self.recommend(nights)
        XCTAssertEqual(at.confidence, .early)
        XCTAssertLessThan(at.shift, 0)
    }

    // 7. 40 nights are never "fairly sure"; 60 clean nights with the effect are.
    func testConfidenceCap() {
        let forty = Self.recommend(Self.makeNights(n: 40, seed: 12, shape: Self.earlyIsBetter))
        XCTAssertNotEqual(forty.confidence, .fair)
        let sixty = Self.recommend(Self.makeNights(n: 60, seed: 12, shape: Self.earlyIsBetter))
        XCTAssertEqual(sixty.confidence, .fair)
        XCTAssertTrue(sixty.confidenceText.hasPrefix("Fairly sure from 60 nights"))
    }

    // 8. A planted HRV effect: an earlier window, led by HRV.
    func testPlantedEffect() {
        let r = Self.recommend(Self.makeNights(n: 40, seed: 13, shape: Self.earlyIsBetter))
        XCTAssertTrue((-45 ... -15).contains(r.shift), "shift \(r.shift)")
        XCTAssertEqual(r.evidence?.lead, .hrv)
        XCTAssertEqual(r.basis, .personal)
        XCTAssertTrue(r.why.contains("higher"), r.why)
        XCTAssertTrue(r.why.contains("at the same sleep length"))
    }

    // 9. Noise only: almost never a claim.
    func testNullRarelyClaims() {
        let claims = (0..<200).filter { seed in Self.claims(Self.recommend(Self.makeNights(n: 56, seed: UInt64(1000 + seed)))) }.count
        XCTAssertLessThanOrEqual(claims, 20)
    }

    // MARK: 10–13 Confounders

    // 10. HRV follows sleep length only, and later nights are shorter: no claim.
    func testLengthConfoundMakesNoClaim() {
        var claims = 0
        for seed in 0..<40 {
            let nights = Self.makeNights(n: 56, seed: UInt64(200 + seed)) { d, g in
                let short = min(max(60 + 0.5 * 60 * d.z + 0.866 * 60 * g.normal(), 0), 180)
                d.asleep = Self.need - Int(short)
                d.hrv = -8 * short / 60 + g.normal() * 3
                d.rhr = 2 * short / 60 + g.normal()
            }
            if Self.claims(Self.recommend(nights)) { claims += 1 }
        }
        XCTAssertLessThanOrEqual(claims, 4)
    }

    // 11. Bedtime and length move together: can't be separated.
    func testNotSeparable() {
        let nights = Self.makeNights(n: 40, seed: 21) { d, g in
            let short = min(max(90 + 60 * d.z, 0), 240)
            d.asleep = Self.need - Int(short)
            Self.earlyIsBetter(&d, &g)
        }
        let r = Self.recommend(nights)
        XCTAssertEqual(r.caveat, .notSeparable)
        XCTAssertEqual(r.shift, 0)
    }

    /// Clean noise nights plus late, rough nights with `flag`.
    static func withRoughLateNights(flag: SleepTiming.Flags) -> [SleepTiming.Night] {
        makeNights(n: 44, seed: 31) { d, g in
            if d.index % 4 == 3 {
                d.onset = 90 + Int(g.rng.next() * 60)
                d.z = 1.5
                d.hrv -= 15
                d.rhr += 4
                d.flags = flag
            }
        }
    }

    // 12. Nights after drinks are left out.
    func testAlcoholNightsExcluded() {
        let flagged = Self.recommend(Self.withRoughLateNights(flag: .alcohol))
        XCTAssertEqual(flagged.nightsUsed, 33)
        XCTAssertFalse(Self.claims(flagged))
        let unflagged = Self.recommend(Self.withRoughLateNights(flag: []))
        XCTAssertEqual(unflagged.nightsUsed, 44)
        XCTAssertTrue(Self.claims(unflagged), "without the flag the rough late nights would count")
    }

    // 13. Exam stretches likewise.
    func testExamNightsExcluded() {
        let flagged = Self.recommend(Self.withRoughLateNights(flag: .exam))
        XCTAssertEqual(flagged.nightsUsed, 33)
        XCTAssertFalse(Self.claims(flagged))
    }

    // MARK: 14–15 Cycle and pill

    // 14. Natural cycle: luteal nights get their 4% back, and a best group
    // short of luteal nights is downgraded.
    func testNaturalCycleAdjustedAndBalanced() {
        let luteal = SleepTiming.Night(record: NightRecord(wakeDay: Self.day0, bedtime: -12, sleepOnset: 0, wake: 495, asleepMinutes: 480,
                                                           outcome: .init(hrvDeltaPct: -4, restingHRDelta: 1.5)),
                                       cycleShift: .luteal, wakeWeek: 0)
        XCTAssertEqual(SleepTiming.metrics(luteal).hrv, 0)
        XCTAssertEqual(SleepTiming.metrics(luteal).rhr, 0)

        let nights = Self.makeNights(n: 60, seed: 12) { d, g in
            Self.earlyIsBetter(&d, &g)
            if d.z > -0.2 && d.index % 3 != 0 {
                d.cycleShift = .luteal
                d.flags.insert(.luteal)
                d.hrv -= 4
                d.rhr += 1.5
            }
        }
        let r = Self.recommend(nights)
        XCTAssertLessThan(r.shift, 0)
        XCTAssertEqual(r.caveat, .lutealImbalance)
        XCTAssertEqual(r.confidence, .early, "a balance warning keeps it from fairly sure")
    }

    // 15. Pill: no cycle shift, but most break-week nights in the best group.
    func testPillBreakWeekImbalance() {
        let nights = Self.makeNights(n: 60, seed: 12) { d, g in
            Self.earlyIsBetter(&d, &g)
            if Self.isEarly(d) && d.index % 5 != 0 { d.flags.insert(.breakWeek) }
        }
        let r = Self.recommend(nights)
        XCTAssertEqual(r.caveat, .breakWeekImbalance)
        XCTAssertNotEqual(r.confidence, .fair)
    }

    // MARK: 16–19 Guards on the finding

    // 16. An effect in the older half only doesn't count.
    func testSplitHalfMustHold() {
        let nights = Self.makeNights(n: 56, seed: 41) { d, g in
            if d.index < 28 { if Self.isEarly(d) { d.hrv += 14; d.rhr -= 3 } }
            else if Self.isEarly(d) { d.hrv -= 3 }
        }
        let r = Self.recommend(nights)
        XCTAssertFalse(Self.claims(r))
    }

    // 17. HRV favours earlier nights but resting heart rate clearly opposes.
    func testMetricDisagreement() {
        let nights = Self.makeNights(n: 56, seed: 42) { d, g in
            if Self.isEarly(d) { d.hrv += 10; d.rhr += 3 }
        }
        XCTAssertFalse(Self.claims(Self.recommend(nights)))
    }

    // 18. The middle third did best: her usual time is working.
    func testMiddleBest() {
        let nights = Self.makeNights(n: 56, seed: 43) { d, g in
            if abs(d.z) < 0.43 { d.hrv += 10; d.rhr -= 2 }
        }
        let r = Self.recommend(nights)
        XCTAssertEqual(r.shift, 0)
        XCTAssertEqual(r.caveat, .usualWorks)
    }

    // 19. The later third did best: never a later window.
    func testLateBestNeverLater() {
        let nights = Self.makeNights(n: 56, seed: 44) { d, g in
            if d.z > 0.43 { d.hrv += 10; d.rhr -= 2 }
        }
        let r = Self.recommend(nights)
        XCTAssertEqual(r.shift, 0)
        XCTAssertNil(r.evidence)
        XCTAssertEqual(r.caveat, .laterNotWorse)
        XCTAssertEqual(r.bed.end, SleepTiming.roundDown5(Self.upBy - Self.need - 12))
    }

    // MARK: 20–22 Window, wake, clock change

    // 20. Before a free morning: at most an hour later, 5-minute edges, 30 wide.
    func testFreeNightWindow() {
        for jetlag in [0, 25, 47, 90, 200] {
            let c = Self.chronotype(msfsc: 300, jetlag: jetlag)
            let nights = Self.makeNights(n: 5, seed: 5)
            let weekday = SleepTiming.recommend(Self.input(nights, chronotype: c, free: 5, work: 9))
            let free = SleepTiming.recommend(Self.input(nights, chronotype: c, free: 5, work: 9, tomorrowIsFree: true))
            XCTAssertLessThanOrEqual(free.bed.end - weekday.bed.end, SleepTiming.freeNightCap)
            XCTAssertGreaterThanOrEqual(free.bed.end, weekday.bed.end)
            XCTAssertEqual(free.bed.length, 30)
            XCTAssertEqual(free.bed.start % 5, 0)
            XCTAssertEqual(free.bed.end % 5, 0)
        }
    }

    // 21. Wake is the planner's smart alarm window for "bed by", rounded out, never past up-by.
    func testWakeComesFromThePlanner() {
        let r = Self.recommend(Self.makeNights(n: 5, seed: 6))
        let plan = WakePlanner.plan(.init(bedtime: r.bed.end, latency: 12, cycleLength: 92, deadline: Self.upBy,
                                          tonightNeed: Self.need, windowLength: 22))!
        XCTAssertEqual(r.wake.start, SleepTiming.roundDown5(plan.alarmWindow.start))
        XCTAssertEqual(r.wake.end, min(SleepTiming.roundUp5(plan.alarmWindow.end), Self.upBy))
        XCTAssertLessThanOrEqual(r.wake.end, Self.upBy)

        // No whole cycle fits: the 25 minutes up to up-by.
        let none = SleepTiming.recommend(.init(nights: [], need: 60, upBy: 30))
        XCTAssertEqual(none.wake, TimeRange(5, 30))
    }

    // 22. The clock-change night is left out, and the change moves bed-by.
    func testClockChange() {
        var nights = Self.makeNights(n: 30, seed: 7)
        nights[29].flags = .clockChange
        XCTAssertEqual(Self.recommend(nights).nightsUsed, 29)
        let usual = Self.recommend(Array(nights.prefix(5)))
        let fallBack = Self.recommend(Array(nights.prefix(5)), clockShift: -60)
        XCTAssertEqual(fallBack.bed.end - usual.bed.end, 60)
    }

    // MARK: 23–26 Regularity, wording, Tonight, determinism

    // 23. 9 of the last 14 nights within 30 minutes of the window's middle; midnight wraps.
    func testRegularity() {
        // Window 11:15–11:45pm, latency 12: middle onset 11:42pm (−18).
        let onsets = [-40, -18, 10, -48, 12, -10, -30, 0, -20] + [60, 90, -90, 120, 45]
        let nights = onsets.enumerated().map { i, onset in
            SleepTiming.Night(record: NightRecord(wakeDay: Calendar.current.date(byAdding: .day, value: i, to: Self.day0)!,
                                                  bedtime: onset - 12, sleepOnset: onset, wake: 480, asleepMinutes: 470),
                              wakeWeek: i / 7)
        }
        let r = Self.recommend(nights)
        XCTAssertEqual(r.bed, TimeRange(-45, -15))
        XCTAssertEqual(r.regularityOf, 14)
        XCTAssertEqual(r.regularityHits, 9)
        XCTAssertNotNil(r.onsetSD)
        XCTAssertEqual(SleepTiming.circularDifference(20, 1430), 30, "12:20am and 11:50pm are 30 minutes apart")
        XCTAssertEqual(SleepTiming.circularDifference(1430, 20), -30)
    }

    // 24. Five-minute edges, no causal or "best possible" words, HRV sentence only at 3% or more.
    func testWording() {
        let results = [Self.recommend(Self.makeNights(n: 10, seed: 1)),
                       Self.recommend(Self.makeNights(n: 40, seed: 13, shape: Self.earlyIsBetter)),
                       SleepTiming.recommend(Self.input(Self.makeNights(n: 5, seed: 3), chronotype: Self.chronotype(msfsc: 360), free: 5, work: 9))]
        let texts = results.flatMap { [$0.why, $0.confidenceText, $0.clockNote ?? ""] } + SleepTiming.Caveat.allCases.map(\.text)
        for text in texts {
            for word in ["because", "optimal", "ideal", "healthy", "proven"] {
                XCTAssertFalse(text.lowercased().contains(word), "\"\(word)\" in: \(text)")
            }
        }
        for r in results {
            XCTAssertEqual(r.bed.start % 5, 0); XCTAssertEqual(r.bed.end % 5, 0)
            XCTAssertEqual(r.wake.start % 5, 0)
        }
        let small = SleepTiming.Evidence(lead: .restingHR, delta: 2, bestNights: 12, worstNights: 12, onsetEdge: -30,
                                         bestOnsets: TimeRange(-90, -30), feltBetter: true)
        XCTAssertEqual(SleepTiming.sentence(for: small),
                       "Your resting heart rate was 2 bpm lower after nights you were asleep by 11:30pm, at the same sleep length, and you felt a bit better.")
        // A 2% HRV difference never leads.
        let tiny = Self.recommend(Self.makeNights(n: 60, seed: 12) { d, _ in if Self.isEarly(d) { d.hrv += 2; d.rhr -= 2 } })
        XCTAssertNotEqual(tiny.evidence?.lead, .hrv)
    }

    // 25. Tonight never asks for a later bedtime than the window: the
    // need-based bedtime is at or after "bed by".
    func testConsistentWithTonight() {
        let r = Self.recommend(Self.makeNights(n: 40, seed: 13, shape: Self.earlyIsBetter))
        let lateBed = r.bed.end + 120
        let plan = WakePlanner.plan(.init(bedtime: lateBed, latency: 12, deadline: Self.upBy, tonightNeed: Self.need))
        let tonight = TonightPlan(need: TonightNeed(base: Self.need, debt: 0), bedtime: lateBed, upBy: Self.upBy, plan: plan)
        let cover = try! XCTUnwrap(tonight.bedtimeToCoverNeed)
        XCTAssertGreaterThanOrEqual(cover, r.bed.end)
        XCTAssertEqual(min(r.bed.end, cover), r.bed.end)
    }

    // 26. The same input gives the same result.
    func testDeterministic() {
        let nights = Self.makeNights(n: 60, seed: 12, shape: Self.earlyIsBetter)
        XCTAssertEqual(Self.recommend(nights), Self.recommend(nights))
    }

    // MARK: Helpers

    func testLeastSquaresAndSlots() {
        // y = 2 + 3x
        let slopes = SleepTiming.leastSquares([2, 5, 8, 11], [[0, 1, 2, 3]])
        XCTAssertEqual(slopes?.first ?? 0, 3, accuracy: 1e-9)
        // A slope with the wrong sign (more short = better) is dropped.
        let adjusted = SleepTiming.removeLengthAndJolt([1, 2, 3, 4], shortfall: [0, 1, 2, 3], jolt: [0, 0, 0, 0], allowLength: true)
        XCTAssertEqual(adjusted?.compactMap { $0 }, [1, 2, 3, 4])
        let slots = SleepTiming.slots(Self.makeNights(n: 30, seed: 8))
        XCTAssertEqual(slots.map(\.nights).reduce(0, +), 30)
        XCTAssertTrue(slots.allSatisfy { $0.start % 30 == 0 })
    }
}

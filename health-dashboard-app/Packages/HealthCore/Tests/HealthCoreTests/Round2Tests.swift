import XCTest
@testable import HealthCore

/// Tests for the fixes from test round 2 (tester and item in each comment).
final class Round2CycleTests: XCTestCase {
    // Maya N3: a long gap is normal on the hormonal IUD and mini pill.
    func testHormonalIUDAndMiniPillAreNeverOverdue() {
        for bc in [BirthControl.hormonalIUD, .miniPill] {
            let d = CycleDisplay.make(tracking: true, irregular: false, birthControl: bc, cycleDay: 60, cycleLength: 29)
            XCTAssertEqual(d, .suppressed(bc))
            XCTAssertTrue(d.cyclePhaseUnknown)
        }
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: false, birthControl: .copperIUD, cycleDay: 40, cycleLength: 29),
                       .overdue(day: 40, typicalLength: 29))
        XCTAssertFalse(CycleDisplay.suppressed(.implant).cyclePhaseUnknown)
    }

    // Maya N7 / Riley R2: the grace days past her length are "due around now":
    // no late-luteal adjustment, phase unknown for the sick check.
    func testGraceDaysDropLutealAdjustments() {
        let d = CycleDisplay.make(tracking: true, irregular: false, birthControl: nil, cycleDay: 30, cycleLength: 29)
        XCTAssertTrue(d.isPastUsualLength)
        XCTAssertFalse(d.isLateLuteal)
        XCTAssertTrue(d.cyclePhaseUnknown)
        let inside = CycleDisplay.make(tracking: true, irregular: false, birthControl: nil, cycleDay: 26, cycleLength: 29)
        XCTAssertFalse(inside.isPastUsualLength)
        XCTAssertTrue(inside.isLateLuteal)
        XCTAssertFalse(inside.cyclePhaseUnknown)
        XCTAssertTrue(CycleDisplay.irregular(daysSinceLastPeriod: 40).cyclePhaseUnknown)
    }

    // Riley R1: long cycles never fall back to a made-up 29.
    func testLongCyclesHaveNoUsualLength() {
        let cal = Calendar(identifier: .gregorian)
        let d0 = Date(timeIntervalSince1970: 1_780_000_000)
        func starts(_ gaps: [Int]) -> [Date] {
            var out = [d0]
            for g in gaps { out.append(cal.date(byAdding: .day, value: g, to: out.last!)!) }
            return out
        }
        let long = CycleEstimator.lengths(periodStarts: starts([52, 61, 48]), calendar: cal)
        XCTAssertTrue(long.runLong)
        XCTAssertNil(long.usual)
        XCTAssertNil(CycleEstimator.averageLength(periodStarts: starts([52, 61, 48]), calendar: cal))
        let mixed = CycleEstimator.lengths(periodStarts: starts([30, 31, 58]), calendar: cal)
        XCTAssertFalse(mixed.runLong)
        XCTAssertEqual(mixed.usual, 31)
        XCTAssertEqual(mixed.gaps, [30, 31, 58])
    }
}

final class Round2SignalTests: XCTestCase {
    // Priya P6: without a resting heart rate baseline there's no stress level.
    func testNoStressWithoutBaseline() {
        let samples = (8...20).map { StressModel.Sample(hour: $0, heartRate: 80, hrv: 40, steps: 100) }
        let day = StressModel.day(samples, restingHR: 0, baselineHRV: 0)
        XCTAssertNil(day.label)
        XCTAssertNil(day.average)
        XCTAssertTrue(day.hours.allSatisfy { $0.level == nil })
    }

    // Priya P8: the hour after a workout is cool-down, not stress.
    func testCoolDownHourIsLeftOut() {
        var samples = (8...12).map { StressModel.Sample(hour: $0, heartRate: 66, hrv: 50, steps: 100) }
        samples.append(StressModel.Sample(hour: 13, heartRate: 150, hrv: 20, steps: 5000))
        samples.append(StressModel.Sample(hour: 14, heartRate: 100, hrv: 25, steps: 200))
        samples.append(StressModel.Sample(hour: 15, heartRate: 66, hrv: 50, steps: 100))
        let day = StressModel.day(samples, restingHR: 62, baselineHRV: 50)
        let cool = try! XCTUnwrap(day.hours.first { $0.hour == 14 })
        XCTAssertTrue(cool.coolingDown)
        XCTAssertNil(cool.level)
        XCTAssertNotNil(day.hours.first { $0.hour == 15 }?.level)
        XCTAssertEqual(day.label, .low)
    }

    // Riley R3: an unknown cycle phase gets the luteal allowance, and says so.
    func testUnknownPhaseGetsTheAllowance() {
        let plain = IllnessSignal.evaluate(restingHRDelta: 4, hrvDeltaPct: -16, respiratoryRateDelta: nil, wristTempDelta: 0.5, lutealPhase: false)
        XCTAssertEqual(plain.confidence, .high)
        XCTAssertFalse(plain.cyclePhaseUnknown)
        let unknown = IllnessSignal.evaluate(restingHRDelta: 4, hrvDeltaPct: -16, respiratoryRateDelta: nil, wristTempDelta: 0.5,
                                             lutealPhase: false, cyclePhaseUnknown: true)
        XCTAssertTrue(unknown.cyclePhaseUnknown)
        XCTAssertLessThan(Self.rank(unknown.confidence), Self.rank(plain.confidence))
        XCTAssertTrue(unknown.factors.contains { $0.note?.contains("can't tell") == true })
    }

    static func rank(_ c: IllnessSignal.Confidence) -> Int { IllnessSignal.Confidence.allCases.firstIndex(of: c)! }

    // Sam N3 / Priya P7: "hard training" is relative to her own usual.
    func testHardTrainingIsRelative() {
        let athlete = Array(repeating: 700.0, count: 14)
        XCTAssertFalse(IllnessSignal.isHardTraining(yesterdayKcal: 750, earlierDaysKcal: athlete))
        XCTAssertTrue(IllnessSignal.isHardTraining(yesterdayKcal: 1100, earlierDaysKcal: athlete))
        let light = Array(repeating: 150.0, count: 14)
        XCTAssertFalse(IllnessSignal.isHardTraining(yesterdayKcal: 280, earlierDaysKcal: light))   // under 5 kcal/kg of 60 kg
        XCTAssertTrue(IllnessSignal.isHardTraining(yesterdayKcal: 320, earlierDaysKcal: light))
        XCTAssertTrue(IllnessSignal.isHardTraining(yesterdayKcal: 500, earlierDaysKcal: []))       // too little history: 8 kcal/kg
        XCTAssertFalse(IllnessSignal.isHardTraining(yesterdayKcal: nil, earlierDaysKcal: light))
    }

    // Round 2 check, now on the FRIEND women's medians: the fitness age and
    // the median at that age agree.
    func testFitnessLevelMatchesTheAge() {
        let vo2 = FitnessAge.average(age: 40)
        XCTAssertEqual(FitnessAge.estimate(vo2Max: vo2), 40)
        XCTAssertEqual(FitnessAge.level(vo2Max: vo2, age: 40), "About average for women in their 40s")
    }

    // Sam N8: compared within alarm and free mornings, a weekend habit isn't
    // credited with the weekend's longer sleep.
    func testStratifiedComparison() {
        let d0 = Date(timeIntervalSince1970: 1_780_000_000)
        var nights: [NightRecord] = []
        for i in 0..<20 {
            let free = i % 4 == 0 || i % 4 == 1
            let late = free ? i % 4 == 0 : i % 8 == 2
            let asleep = (free ? 520 : 420) - (late ? 20 : 0)
            nights.append(NightRecord(wakeDay: d0.addingTimeInterval(Double(i) * 86_400), bedtime: late ? 150 : 30, sleepOnset: 40,
                                      wake: 40 + asleep, asleepMinutes: asleep, alarmUsed: !free))
        }
        let naive = HabitEffect.compare(nights) { $0.bedtime > 120 }
        let matched = HabitEffect.compare(nights, where: { $0.bedtime > 120 }, within: \.alarmUsed)
        XCTAssertGreaterThan(naive.asleepDelta, 0)     // late nights look longer…
        XCTAssertEqual(matched.asleepDelta, -20)       // …but each one costs 20 minutes
        XCTAssertEqual(matched.withCount, naive.withCount)
    }
}

final class Round2CaffeineTests: XCTestCase {
    // Maya N2 / Sam N11: no "latest time" that has already gone by.
    func testLatestTimeIsNilWhenItHasPassed() {
        // The pill's half-life, 12:30am bedtime: a latte by about 2pm.
        let pill = CaffeineModel.estrogenHalfLifeHours
        let latest = try! XCTUnwrap(CaffeineModel.latestTime(forMg: 130, bedtime: 1470, halfLifeHours: pill))
        XCTAssertLessThan(latest, 900)
        XCTAssertNil(CaffeineModel.latestTime(forMg: 130, bedtime: 1470, halfLifeHours: pill, notBefore: 900))
        XCTAssertNotNil(CaffeineModel.latestTime(forMg: 130, bedtime: 1470, notBefore: 900))
        // With the 50 mg line, a pill user with a 12:30am bedtime has until
        // 1:00pm for the reference coffee (140 mg).
        XCTAssertEqual(CaffeineModel.cutoff(bedtime: 1470, halfLifeHours: pill, mg: 140), 780)
        // A smaller drink fits later in the day.
        XCTAssertNotNil(CaffeineModel.latestTime(forMg: 64, bedtime: 1470, halfLifeHours: pill, notBefore: 720))
    }

    func testLargestDoseFits() {
        let pill = CaffeineModel.estrogenHalfLifeHours, limit = CaffeineModel.bedtimeLimitMg
        let mg = CaffeineModel.largestDose(at: 480, bedtime: 1470, halfLifeHours: pill)
        XCTAssertGreaterThan(mg, 0)
        XCTAssertEqual(mg % 5, 0)
        XCTAssertLessThan(CaffeineModel.amount(at: 1470, doses: [CaffeineDose(time: 480, mg: mg)], halfLifeHours: pill), limit)
        XCTAssertGreaterThanOrEqual(CaffeineModel.amount(at: 1470, doses: [CaffeineDose(time: 480, mg: mg + 10)], halfLifeHours: pill), limit)
        XCTAssertEqual(CaffeineModel.largestDose(at: 480, bedtime: 1470, existing: [CaffeineDose(time: 1200, mg: 200)]), 0)
    }

    // Jordan: a drink just logged doesn't read as 0 mg.
    func testJustLoggedIsNotZero() {
        XCTAssertGreaterThan(CaffeineModel.amount(at: 600, doses: [CaffeineDose(time: 600, mg: 130)]), 5)
        XCTAssertEqual(CaffeineModel.amount(at: 599, doses: [CaffeineDose(time: 600, mg: 130)]), 0)
    }

    // Maya N2: no "you woke late" note when the cutoff is before her window.
    func testTimingWithoutAWindow() {
        let e = EnergyModel.day(.init(wake: 450, asleepMinutes: 460, sleepDebt: 0, habitualMidSleep: 262, habitualSleepOnset: 1482, bedtime: 1470))
        let t = CaffeineModel.timing(energy: e, cutoff: CaffeineModel.cutoff(bedtime: 1470, halfLifeHours: 20, mg: 140), firstDrinkAt: nil)
        XCTAssertTrue(t.cutoffBeforeWindow)
        XCTAssertEqual(t.bestWindow.length, 0)
        XCTAssertFalse(t.note.lowercased().contains("woke late"))
        XCTAssertFalse(t.note.contains("walk"))
        let normal = CaffeineModel.timing(energy: e, cutoff: CaffeineModel.cutoff(bedtime: 1470), firstDrinkAt: nil)
        XCTAssertFalse(normal.cutoffBeforeWindow)
    }
}

final class Round2ScoreTests: XCTestCase {
    func input(wake: Minutes = 480, asleep: Int = 460, need: Int? = 470) -> EnergyModel.Input {
        .init(wake: wake, asleepMinutes: asleep, sleepDebt: 0, habitualMidSleep: 262, habitualSleepOnset: 1482, bedtime: 1470, sleepNeed: need)
    }

    // Sam N4: sleep past her need doesn't keep adding energy…
    func testSleepBenefitPlateausAtNeed() {
        XCTAssertEqual(EnergyModel.day(input(asleep: 470)).score, EnergyModel.day(input(asleep: 600)).score)
        XCTAssertLessThan(EnergyModel.day(input(asleep: 400)).score, EnergyModel.day(input(asleep: 470)).score)
    }

    // …and a late wake isn't marked down for the night she'd sleep through.
    func testLateWakeIsOnlyMildlyLower() {
        let usual = EnergyModel.day(input(wake: 480)).score
        let late = EnergyModel.day(input(wake: 840)).score
        XCTAssertLessThan(late, usual)
        XCTAssertGreaterThanOrEqual(late, usual - 8)
    }

    // Sam leftover: Recovery bands scale with her own day-to-day spread.
    func testRecoveryLabelScales() {
        XCTAssertEqual(Recovery.label(84, usual: 78), "Ready to push")
        XCTAssertEqual(Recovery.label(84, usual: 78, spread: 16), "On track")
        XCTAssertEqual(Recovery.label(70, usual: 78, spread: 16), "Take it steady")
        XCTAssertEqual(Recovery.label(56, usual: 78, spread: 16), "Take it steady")
        XCTAssertEqual(Recovery.label(40, usual: 78, spread: 16), "Go easy today")
        XCTAssertEqual(Recovery.band(spread: 4), 5)
        XCTAssertEqual(Recovery.band(spread: 40), 12)
    }

    // Sam N9 / Jordan J7: caffeine and daylight are only tested against how
    // she said she felt, never against the sleep-only energy model.
    func testRecapHabitsAreNotCircular() {
        let d0 = Date(timeIntervalSince1970: 1_780_000_000)
        func day(_ i: Int, energy: Int, checkIn: Double?, daylight: Int) -> DaySummary {
            DaySummary(date: d0.addingTimeInterval(Double(i) * 86_400), energy: energy, asleep: 470, bedtime: 30, wake: 480,
                       wokeFromLightSleep: true, daylightMinutes: daylight, caffeineMg: 100, lastCaffeine: 600, checkIn: checkIn)
        }
        let noCheckIns = (0..<6).map { day($0, energy: 60 + $0 * 4, checkIn: nil, daylight: $0 >= 3 ? 40 : 5) }
        let a = try! XCTUnwrap(WeekRecap.make(days: noCheckIns, need: 470, bestWindow: nil))
        XCTAssertFalse(a.habitsFromCheckIns)
        XCTAssertFalse(a.bestDayHabits.contains { $0.contains("daylight") })
        let withCheckIns = (0..<6).map { day($0, energy: 70, checkIn: $0 >= 3 ? 4 : 2, daylight: $0 >= 3 ? 40 : 5) }
        let b = try! XCTUnwrap(WeekRecap.make(days: withCheckIns, need: 470, bestWindow: nil))
        XCTAssertTrue(b.habitsFromCheckIns)
        XCTAssertTrue(b.bestDayHabits.contains { $0.contains("daylight") })
        // The app-wide late threshold is used when given.
        let late = (0..<4).map { day($0, energy: 70 - $0, checkIn: nil, daylight: 20) }
        XCTAssertTrue(try! XCTUnwrap(WeekRecap.make(days: late, need: 470, bestWindow: nil, lateThreshold: 20)).worstDayIssues.contains { $0.hasPrefix("Bed at") })
    }
}

final class Round2SleepNeedTests: XCTestCase {
    // Sam leftover: pure noise must not read as "Fairly sure".
    func testNoiseStaysLearning() {
        var rng = SeededRandom(seed: 3)
        let d0 = Date(timeIntervalSince1970: 1_780_000_000)
        let nights = (0..<40).map { i -> NightRecord in
            let asleep = 360 + Int(rng.next() * 200)
            return NightRecord(wakeDay: d0.addingTimeInterval(Double(i) * 86_400), bedtime: 30, sleepOnset: 40, wake: 40 + asleep,
                               asleepMinutes: asleep, outcome: NextDayOutcome(hrvDeltaPct: (rng.next() - 0.5) * 30,
                                                                              restingHRDelta: (rng.next() - 0.5) * 6))
        }
        XCTAssertEqual(SleepNeedEstimator.estimate(from: nights).confidence, .learning)
    }

    // Sam N1: the weekend rebound alone never makes it "Fairly sure", and its
    // weight grows with samples.
    func testReboundAloneIsNotConfident() {
        let d0 = Date(timeIntervalSince1970: 1_780_000_000)
        let nights = (0..<30).map { i in
            NightRecord(wakeDay: d0.addingTimeInterval(Double(i) * 86_400), bedtime: 30, sleepOnset: 40, wake: 540, asleepMinutes: 500, alarmUsed: false)
        }
        let est = SleepNeedEstimator.estimate(from: nights)
        XCTAssertEqual(est.confidence, .learning)
        let rebound = try! XCTUnwrap(est.methods.first { $0.kind == .rebound })
        XCTAssertLessThanOrEqual(rebound.weight, 0.7)
    }
}

final class Round2WakePlanTests: XCTestCase {
    // Jordan J10: the night the clocks go back has an extra hour in it.
    func testFallBackNightPlansOnElapsedTime() {
        let normal = try! XCTUnwrap(WakePlanner.plan(.init(bedtime: 0, deadline: 480, tonightNeed: 520)))
        let fallBack = try! XCTUnwrap(WakePlanner.plan(.init(bedtime: 0, deadline: 480, tonightNeed: 520, clockShift: -60)))
        XCTAssertGreaterThanOrEqual(fallBack.cycles, normal.cycles)
        XCTAssertLessThanOrEqual(fallBack.wake, 480)
        XCTAssertLessThanOrEqual(fallBack.alarmWindow.end, 480)
        // 9h of elapsed time: the last cycle ends 68 minutes before up-by,
        // so she sleeps until up-by on the new clock (Park 1).
        XCTAssertFalse(fallBack.endsCycle)
        XCTAssertEqual(fallBack.wake, 480)
        XCTAssertEqual(fallBack.asleep, 540 - 12)
        XCTAssertTrue(fallBack.reasons.first!.detail.contains(Clock.format(fallBack.wake)))
        // A night where a cycle ends close to up-by on the new clock wakes there.
        let close = try! XCTUnwrap(WakePlanner.plan(.init(bedtime: 0, deadline: 430, tonightNeed: 470, clockShift: -60)))
        XCTAssertTrue(close.endsCycle)
        XCTAssertEqual(close.wake, 12 + close.cycles * 92 - 60)
    }

    /// Round 3 H10: the cutoff for the 140 mg reference coffee comes earlier
    /// than for 100 mg, and still leaves under the bedtime limit.
    func testCutoffForReferenceCoffee() {
        let c140 = CaffeineModel.cutoff(bedtime: 1470, mg: 140)
        XCTAssertLessThan(c140, CaffeineModel.cutoff(bedtime: 1470))
        XCTAssertEqual(Clock.format(c140), "4:30pm")
        XCTAssertLessThan(CaffeineModel.amount(at: 1470, doses: [CaffeineDose(time: c140, mg: 140)]), CaffeineModel.bedtimeLimitMg)
    }

    /// Round 3 J1: a hormonal IUD or mini pill with no period logged gets its
    /// method's view, not the irregular "log your next period" one.
    func testNoPeriodHormonalIUDIsSuppressed() {
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: false, birthControl: .hormonalIUD, cycleDay: nil, cycleLength: 29),
                       .suppressed(.hormonalIUD))
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: true, birthControl: .miniPill, cycleDay: nil, cycleLength: 29),
                       .suppressed(.miniPill))
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: false, birthControl: nil, cycleDay: nil, cycleLength: 29),
                       .irregular(daysSinceLastPeriod: nil))
    }
}

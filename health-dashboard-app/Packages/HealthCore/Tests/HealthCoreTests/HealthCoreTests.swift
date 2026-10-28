import XCTest
@testable import HealthCore

final class ClockTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(Clock.format(502), "8:22am")
        XCTAssertEqual(Clock.format(-5), "11:55pm")
        XCTAssertEqual(Clock.format(30), "12:30am")
        XCTAssertEqual(Clock.duration(460), "7h 40m")
        XCTAssertEqual(Clock.duration(35), "35 min")
        XCTAssertEqual(TimeRange(860, 970).label, "2:20–4:10pm")
        XCTAssertEqual(TimeRange(630, 770).label, "10:30am–12:50pm")
    }
}

final class SleepNeedTests: XCTestCase {
    /// 71 synthetic nights whose next-day numbers stop improving at 7h 50m.
    func makeNights(knee: Double = 470, count: Int = 71) -> [NightRecord] {
        var rng = SeededRandom(seed: 7)
        let day0 = Date(timeIntervalSince1970: 1_780_000_000)
        return (0..<count).map { i in
            let asleep = 330.0 + rng.next() * 230
            let short = max(knee - asleep, 0) / 60
            let outcome = NextDayOutcome(
                hrvDeltaPct: 2 - 6 * short + (rng.next() - 0.5) * 2,
                restingHRDelta: -1 + 2.2 * short + (rng.next() - 0.5),
                checkIn: 4 - 0.55 * max(415 - asleep, 0) / 60 + (rng.next() - 0.5) * 0.4,
                energyScore: 74 - 10 * short + (rng.next() - 0.5) * 4)
            return NightRecord(wakeDay: day0.addingTimeInterval(Double(i) * 86_400), bedtime: 30, sleepOnset: 42,
                               wake: 42 + Int(asleep), asleepMinutes: Int(asleep), outcome: outcome)
        }
    }

    func testFindsTheKnee() {
        let est = SleepNeedEstimator.estimate(from: makeNights())
        XCTAssertEqual(Double(est.minutes), 470, accuracy: 20)
        XCTAssertEqual(est.confidence, .good)
        XCTAssertTrue(est.range.contains(est.minutes))
    }

    func testFeelingFinePlateausEarlier() {
        let est = SleepNeedEstimator.estimate(from: makeNights())
        let felt = try! XCTUnwrap(est.subjectiveKnee)
        XCTAssertLessThan(felt, est.minutes - 30)
    }

    func testFewNightsLeanOnPriorAndStayInLimits() {
        let est = SleepNeedEstimator.estimate(from: Array(makeNights().prefix(5)))
        XCTAssertEqual(est.confidence, .learning)
        XCTAssertTrue(SleepNeedEstimator.researchLimits.contains(est.minutes))
    }

    func testReboundFromFreeNights() {
        let day0 = Date(timeIntervalSince1970: 1_780_000_000)
        let lengths = [560, 520, 478, 472, 476, 470]
        let nights = lengths.enumerated().map { i, m in
            NightRecord(wakeDay: day0.addingTimeInterval(Double(i) * 86_400), bedtime: 0, sleepOnset: 10, wake: 10 + m, asleepMinutes: m, alarmUsed: false)
        }
        // Runs of 2+ free nights count from their second night (W19: the old
        // rule needed 3+ and skipped two, so a weekend never counted).
        let r = try! XCTUnwrap(SleepNeedEstimator.reboundEstimate(nights))
        XCTAssertEqual(r.minutes, 476)
        XCTAssertEqual(r.samples, 5)
    }

    func testDebtAndTonightNeed() {
        let debt = SleepDebt.minutes(need: 470, lastNightsNewestFirst: Array(repeating: 459, count: 14))
        XCTAssertEqual(debt, 154)
        let tonight = TonightNeed(base: 470, debt: 160, lateLuteal: true)
        XCTAssertEqual(tonight.total, 495)   // 7h 50m + 15m + 10m = 8h 15m
    }
}

final class WakeTests: XCTestCase {
    func testAshleysPlan() {
        let plan = try! XCTUnwrap(WakePlanner.plan(.init(bedtime: 30, deadline: 510, tonightNeed: 495,
                                                         bestWindow: TimeRange(470, 510), currentAlarmLatest: 465)))
        XCTAssertEqual(Clock.format(plan.wake), "8:22am")
        XCTAssertEqual(plan.cycles, 5)
        XCTAssertEqual(plan.alarmWindow, TimeRange(472, 505))
        XCTAssertEqual(plan.shortfall, 35)
        XCTAssertEqual(plan.currentAlarmMinutesIntoCycle, 55)
        XCTAssertEqual(plan.reasons.map(\.ok), [true, true, false])
    }

    func testEarlyDeadlineIsShort() {
        // The last cycle ends at 6:50am, 40 minutes before up-by: too much
        // sleep to give up, so she sleeps until 7:30am (Park 1).
        let plan = try! XCTUnwrap(WakePlanner.plan(.init(bedtime: 30, deadline: 450, tonightNeed: 495, bestWindow: TimeRange(470, 510))))
        XCTAssertEqual(Clock.format(plan.wake), "7:30am")
        XCTAssertFalse(plan.endsCycle)
        XCTAssertFalse(plan.reasons[1].ok)
        XCTAssertNotNil(plan.bedtimeToCoverNeed)
    }

    // Park 1: bed 12:30am, up by 8:00am. The last cycle ends at 6:50am,
    // 70 minutes early; the plan sleeps until 8:00am and the smart alarm
    // window ends at 8:00am.
    func testNeverWakesMoreThan25MinutesEarly() {
        let plan = try! XCTUnwrap(WakePlanner.plan(.init(bedtime: 30, deadline: 480, tonightNeed: 480, windowLength: 22)))
        XCTAssertEqual(Clock.format(plan.wake), "8:00am")
        XCTAssertFalse(plan.endsCycle)
        XCTAssertEqual(plan.asleep, 480 - 42)
        XCTAssertEqual(plan.alarmWindow, TimeRange(455, 480))
        // Whatever the bedtime, the plan never gives up more than 25 minutes.
        for bed in stride(from: -120, through: 60, by: 1) {
            guard let p = WakePlanner.plan(.init(bedtime: bed, deadline: 480, tonightNeed: 480, windowLength: 22)) else { continue }
            XCTAssertLessThanOrEqual(480 - p.wake, WakePlanner.maxCycleTrade)
            XCTAssertLessThanOrEqual(p.alarmWindow.end, 480)
            XCTAssertEqual(p.alarmWindow.length, 25)
        }
    }

    // A cycle end that would leave her short when up-by covers the need
    // isn't used.
    func testCycleEndNeverMakesACoveredNightShort() {
        // Onset 11:42pm; cycle 5 ends 7:22am, up-by 7:40am (478 asleep).
        let plan = try! XCTUnwrap(WakePlanner.plan(.init(bedtime: -30, deadline: 460, tonightNeed: 475)))
        XCTAssertFalse(plan.endsCycle)
        XCTAssertEqual(plan.wake, 460)
        XCTAssertEqual(plan.shortfall, 0)
    }

    func testHistoryFindsBestWindow() {
        var rng = SeededRandom(seed: 11)
        var mornings: [Morning] = []
        for (lo, hi, n, mean) in [(380, 418, 6, 2.3), (420, 470, 14, 3.2), (470, 510, 21, 4.0), (510, 570, 9, 3.6), (575, 625, 10, 3.0)] {
            for _ in 0..<n {
                let light = rng.next() > 0.3
                mornings.append(Morning(wake: lo + Int(rng.next() * Double(hi - lo)), wokeFromLightSleep: light,
                                        outcome: mean + (light ? 0.3 : -1.0) + (rng.next() - 0.5) * 0.4))
            }
        }
        let h = WakeHistory.analyze(mornings)
        let w = try! XCTUnwrap(h.bestWindow)
        XCTAssertTrue((460...500).contains(w.start), "best window starts \(w.start)")
        XCTAssertGreaterThan(h.lightSleepAdvantage ?? 0, 0.8)
        XCTAssertEqual(h.buckets.count, 5)
    }
}

final class EnergyTests: XCTestCase {
    func testShapeOfTheDay() {
        let day = EnergyModel.day(.init(wake: 441, asleepMinutes: 455, sleepDebt: 160, habitualMidSleep: 262,
                                        habitualSleepOnset: 1482, bedtime: 1470))
        let peak = try! XCTUnwrap(day.zone(.morningPeak)), dip = try! XCTUnwrap(day.zone(.afternoonDip)), second = try! XCTUnwrap(day.zone(.secondWind))
        XCTAssertTrue((600...780).contains(day.highest.time), "peak at \(Clock.format(day.highest.time))")
        XCTAssertTrue((840...1020).contains(day.lowest.time), "low at \(Clock.format(day.lowest.time))")
        XCTAssertLessThan(peak.range.end, dip.range.start)
        XCTAssertLessThan(dip.range.end, second.range.start)
        XCTAssertEqual(day.zone(.melatonin)?.range, TimeRange(1425, 1485))   // 11:45pm–12:45am
        XCTAssertTrue((30...90).contains(day.score))
    }

    func testMoreDebtMeansLowerScore() {
        func score(_ debt: Int) -> Int {
            EnergyModel.day(.init(wake: 480, asleepMinutes: 460, sleepDebt: debt, habitualMidSleep: 262, habitualSleepOnset: 1482, bedtime: 1470)).score
        }
        XCTAssertGreaterThan(score(0), score(240))
    }
}

final class ChronotypeTests: XCTestCase {
    func testAshleyIsAModerateEveningType() {
        let c = try! XCTUnwrap(Chronotype.compute(
            workNights: [Chronotype.Night(onset: 34, wake: 490)],     // 12:34am–8:10am
            freeNights: [Chronotype.Night(onset: 82, wake: 618)]))    // 1:22am–10:18am
        XCTAssertEqual(c.category, .moderateEvening)
        XCTAssertEqual(Double(c.midSleepFreeCorrected), 322, accuracy: 2)   // ~5:22am
        XCTAssertEqual(c.socialJetlag, 88)                                  // 1h 28m
    }
}

final class CaffeineTests: XCTestCase {
    func testLatteLeftAtBedtime() {
        let left = CaffeineModel.amount(at: 1470, doses: [CaffeineDose(time: 580, mg: 130)])
        XCTAssertEqual(left, 17, accuracy: 3)
    }
    func testCutoff() {
        XCTAssertEqual(Clock.format(CaffeineModel.cutoff(bedtime: 1470)), "2:00pm")
    }
}

final class PlanningTests: XCTestCase {
    func testFallBackKeepClockTimes() {
        let nights = TimeChangePlanner.plan(bedtime: 30, wake: 502, shiftMinutes: -60, strategy: .keepClockTimes)
        XCTAssertEqual(Set(nights.map { Clock.format($0.bedtime) }), ["12:30am"])
        XCTAssertEqual(Set(nights.map { Clock.format($0.wake) }), ["8:22am"])
        XCTAssertEqual(Clock.format(nights[3].wake), "8:22am")
    }
    func testFallBackWakeEarlier() {
        let nights = TimeChangePlanner.plan(bedtime: 30, wake: 502, shiftMinutes: -60, strategy: .useItToWakeEarlier)
        XCTAssertEqual(Clock.format(nights[3].wake), "7:22am")
        XCTAssertEqual(Clock.format(nights[4].bedtime), "11:30pm")
    }
    func testRecovery() {
        XCTAssertEqual(Recovery.score(hrvDeltaPct: -6, restingHRDelta: 2, sleepShortfall: 0), 69)
        XCTAssertEqual(Recovery.label(69, usual: 78), "Take it steady")
    }
    func testCyclePhase() {
        XCTAssertEqual(CycleEstimator.phase(day: 22), .luteal)
        XCTAssertTrue(CycleEstimator.isLateLuteal(day: 22))
        XCTAssertEqual(CycleEstimator.phase(day: 3), .period)
    }
    func testExamPlan() {
        let energy = EnergyModel.day(.init(wake: 502, asleepMinutes: 460, sleepDebt: 160, habitualMidSleep: 262, habitualSleepOnset: 1482, bedtime: 1470))
        let plan = ExamPlanner.plan(examStart: 540, daysUntil: 2, usualBedtime: 30, need: 495, energyTemplate: energy)
        XCTAssertEqual(plan.count, 3)
        let examDay = plan.last!
        XCTAssertLessThanOrEqual(examDay.wake, 540 - 70)
        XCTAssertLessThan(examDay.bedtimeBefore, 30)
        XCTAssertFalse(plan.first!.studyBlocks.isEmpty)
        // Park 2 / Liu 11: never plans less than her need.
        for d in plan {
            XCTAssertGreaterThanOrEqual(d.wake - d.bedtimeBefore - 12, 495)
            XCTAssertEqual(d.alarmWindow, TimeRange(d.wake - 22, d.wake + 3))
        }
    }

    // Whole cycles of her own length, rounded up, when that's within 25
    // minutes of her need; her own latency is used.
    func testExamPlanRoundsCyclesUp() {
        let energy = EnergyModel.day(.init(wake: 480, asleepMinutes: 460, sleepDebt: 0, habitualMidSleep: 262, habitualSleepOnset: 1482, bedtime: 1470))
        let plan = ExamPlanner.plan(examStart: 600, daysUntil: 1, usualBedtime: 30, latency: 20, cycleLength: 85, need: 500, energyTemplate: energy)
        let examDay = plan.last!
        XCTAssertTrue(examDay.endsCycle)
        XCTAssertEqual(examDay.asleep, 6 * 85)                  // 510 ≥ 500
        XCTAssertEqual(examDay.wake - examDay.bedtimeBefore - 20, 510)
        XCTAssertLessThanOrEqual(examDay.wake, 600 - 70)
    }
    func testWeekRecap() {
        let d0 = Date(timeIntervalSince1970: 1_780_000_000)
        let rows: [(Int, Int, Int, Int, Bool, Int, Int, Int?)] = [
            (64, 400, 70, 482, false, 14, 200, 810), (69, 472, 10, 494, true, 24, 130, 585),
            (78, 483, 5, 500, true, 31, 130, 580), (71, 471, 25, 508, true, 22, 130, 615),
            (63, 418, 58, 488, true, 17, 210, 910), (48, 380, 160, 552, false, 8, 250, 820),
            (59, 470, 108, 590, true, 17, 70, 750)]
        let days = rows.enumerated().map { i, r in
            DaySummary(date: d0.addingTimeInterval(Double(i) * 86_400), energy: r.0, asleep: r.1, bedtime: r.2, wake: r.3,
                       wokeFromLightSleep: r.4, daylightMinutes: r.5, caffeineMg: r.6, lastCaffeine: r.7)
        }
        let recap = try! XCTUnwrap(WeekRecap.make(days: days, need: 470, bestWindow: TimeRange(470, 510)))
        XCTAssertEqual(recap.averageEnergy, 65)
        XCTAssertEqual(recap.best.energy, 78)
        XCTAssertEqual(recap.worst.energy, 48)
        XCTAssertEqual(recap.lightSleepWakes, 5)
        XCTAssertFalse(recap.bestDayHabits.isEmpty)
        XCTAssertTrue(recap.worstDayIssues.contains { $0.hasPrefix("Bed at 2:40am") })
    }
}

/// Deterministic random numbers for repeatable tests.
struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

final class BodySignalTests: XCTestCase {
    func testBirthControlChangesTheCycleView() {
        // Pack day comes from the pack (W2), not from the bleed start.
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: false, birthControl: .combinedPill, cycleDay: 3, cycleLength: 28, packDay: 16),
                       .pack(day: 16, activeDays: 21, packLength: 28))
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: false, birthControl: .implant, cycleDay: 16, cycleLength: 28), .suppressed(.implant))
        if case .phases(_, _, let phase) = CycleDisplay.make(tracking: true, irregular: false, birthControl: .hormonalIUD, cycleDay: 22, cycleLength: 29) {
            XCTAssertEqual(phase, .luteal)
        } else { XCTFail("hormonal IUD keeps phases") }
        XCTAssertFalse(CycleDisplay.pack(day: 16, activeDays: 21, packLength: 28).isLateLuteal)
        XCTAssertEqual(BirthControl.combinedPill.ovulation, .stopped)
    }

    func testStress() {
        let samples = (8...21).map { h in
            StressModel.Sample(hour: h, heartRate: h == 15 ? 88 : 74, hrv: h == 15 ? 25 : 42, steps: h == 18 ? 3000 : 100)
        }
        let day = StressModel.day(samples, restingHR: 70, baselineHRV: 46)
        XCTAssertEqual(day.peak?.hour, 15)
        XCTAssertTrue(day.hours.first { $0.hour == 18 }!.active)
        XCTAssertNil(day.hours.first { $0.hour == 18 }!.level)
        XCTAssertNotNil(day.label)
    }

    func testIllness() {
        XCTAssertEqual(IllnessSignal.evaluate(restingHRDelta: 2, hrvDeltaPct: -6, respiratoryRateDelta: 0.2, wristTempDelta: 0.3, lutealPhase: true).confidence, .none)
        XCTAssertEqual(IllnessSignal.evaluate(restingHRDelta: 6, hrvDeltaPct: -20, respiratoryRateDelta: 1.5, wristTempDelta: 0.7, lutealPhase: false).confidence, .high)
    }

    func testFitnessAge() {
        XCTAssertEqual(FitnessAge.estimate(vo2Max: 38.2, sex: .female), 26)
    }

    func testHabitEffectAndStreaks() {
        let d0 = Date(timeIntervalSince1970: 1_780_000_000)
        let nights = (0..<10).map { i in
            NightRecord(wakeDay: d0.addingTimeInterval(Double(i) * 86_400), bedtime: 0, sleepOnset: 10, wake: 470, asleepMinutes: i < 5 ? 400 : 460,
                        outcome: NextDayOutcome(hrvDeltaPct: i < 5 ? -12 : 0))
        }
        let e = HabitEffect.compare(nights) { $0.asleepMinutes < 420 }
        XCTAssertTrue(e.enoughData)   // 5 and 5 (was 3 and 3, W19)
        XCTAssertFalse(HabitEffect.compare(Array(nights.dropFirst())) { $0.asleepMinutes < 420 }.enoughData)   // 4 and 5
        XCTAssertEqual(e.asleepDelta, -60)
        XCTAssertEqual(e.hrvDeltaPct ?? 0, -12, accuracy: 0.01)
        XCTAssertEqual(Streaks.current([true, true, false, true]), 2)
        XCTAssertEqual(Streaks.longest([true, false, true, true, true]), 3)
        let test = CaffeineCutoffTest.make(lastCaffeineByNight: [(600, 480), (700, 470), (800, 460), (950, 420), (960, 410)])
        XCTAssertEqual(test.groups.map(\.label), ["Before 12pm", "12–3pm", "After 3pm"])
    }
}

import XCTest
@testable import HealthCore

/// Round 3 (the real app in the simulator): wrong numbers and contradictions.
final class Round3SleepTests: XCTestCase {
    private let onset = Date(timeIntervalSince1970: 1_790_000_000)

    // N1: the stage timeline adds up to the stage totals exactly, and its
    // span is asleep + awake.
    func testTypicalTimelineMatchesStageTotals() {
        let stages: [SleepStage: Int] = [.deep: 72, .rem: 108, .core: 261, .awake: 14]
        let segments = StageLayout.typical(onset: onset, stageMinutes: stages)
        XCTAssertEqual(StageLayout.totals(segments), stages)
        let span = Int(segments.last!.end.timeIntervalSince(segments.first!.start) / 60)
        XCTAssertEqual(span, 72 + 108 + 261 + 14)
        // Back to back, no gaps.
        for (a, b) in zip(segments, segments.dropFirst()) { XCTAssertEqual(a.end, b.start) }
    }

    // N1: for a session, asleep is the stages without awake, and fell asleep →
    // woke up is at least asleep + awake after falling asleep.
    func testSessionAsleepExcludesAwakeAndFitsTheNight() {
        let stages: [SleepStage: Int] = [.deep: 60, .rem: 90, .core: 240, .awake: 20]
        var segments = StageLayout.typical(onset: onset, stageMinutes: stages)
        // 15 minutes lying awake before falling asleep.
        segments.insert(StageSegment(stage: .awake, start: onset.addingTimeInterval(-900), end: onset), at: 0)
        let s = SleepSession(inBed: onset.addingTimeInterval(-900), wake: segments.last!.end, segments: segments)
        XCTAssertEqual(s.asleepMinutes, 60 + 90 + 240)
        XCTAssertEqual(s.awakeAfterOnsetMinutes, 20)
        let onsetToWake = Int(s.wake.timeIntervalSince(s.sleepOnset) / 60)
        XCTAssertGreaterThanOrEqual(onsetToWake, s.asleepMinutes + s.awakeAfterOnsetMinutes)
    }

    // N16: the sleep need is a round number.
    func testSleepNeedIsRoundedToFiveMinutes() {
        let d0 = Date(timeIntervalSince1970: 1_780_000_000)
        let nights = (0..<20).map { i in
            NightRecord(wakeDay: d0.addingTimeInterval(Double(i) * 86_400), bedtime: 30, sleepOnset: 40,
                        wake: 40 + 451 + i, asleepMinutes: 451 + i)
        }
        XCTAssertEqual(SleepNeedEstimator.estimate(from: nights).minutes % 5, 0)
        XCTAssertEqual(TonightNeed(base: 475, debt: 300).total % 5, 0)
    }
}

final class Round3TonightTests: XCTestCase {
    // N3: one plan; its numbers line up, and a bedtime that leaves less
    // than tonight's need says so.
    func testPlanShorterThanNeedSaysSoAndOffersABedtime() {
        let need = TonightNeed(base: 475, debt: 300)          // + 30 payback
        XCTAssertEqual(need.total, 505)
        let wake = WakePlanner.plan(.init(bedtime: 30, deadline: 510, tonightNeed: need.total, windowLength: 22))
        let plan = TonightPlan(need: need, bedtime: 30, upBy: 510, plan: wake)
        XCTAssertEqual(plan.payback, 30)
        XCTAssertEqual(plan.baseNeed, 475)
        XCTAssertEqual(plan.timeInBedAllowed, 480)
        XCTAssertTrue(plan.bedtimeTooLateForNeed)                // 8h in bed < 8h 25m
        XCTAssertEqual(plan.wake, 502)                           // 8:22am, end of cycle 5
        XCTAssertEqual(plan.expectedAsleep, 460)
        XCTAssertEqual(plan.shortfall, 45)
        XCTAssertFalse(plan.coversNeed)
        // The three wake times: window ends after the best wake, never after up-by.
        let window = try! XCTUnwrap(plan.alarmWindow)
        XCTAssertEqual(window.start, 480)
        XCTAssertEqual(window.end, 505)
        XCTAssertLessThanOrEqual(window.end, plan.upBy)
        let cover = try! XCTUnwrap(plan.bedtimeToCoverNeed)
        XCTAssertEqual(cover % 5, 0)
        XCTAssertLessThan(cover, plan.bedtime)
        // A bedtime that early really does cover it.
        let early = WakePlanner.plan(.init(bedtime: cover, deadline: 510, tonightNeed: need.total, windowLength: 22))
        XCTAssertTrue(TonightPlan(need: need, bedtime: cover, upBy: 510, plan: early).coversNeed)
    }

    func testPlanThatCoversNeedHasNoCoverBedtime() {
        let need = TonightNeed(base: 450, debt: 0)
        let wake = WakePlanner.plan(.init(bedtime: -30, deadline: 510, tonightNeed: need.total))
        let plan = TonightPlan(need: need, bedtime: -30, upBy: 510, plan: wake)
        XCTAssertTrue(plan.coversNeed)
        XCTAssertNil(plan.bedtimeToCoverNeed)
        XCTAssertFalse(plan.bedtimeTooLateForNeed)
    }

    // The night the clocks fall back has an extra hour in bed.
    func testFallBackAddsAnHourInBed() {
        let need = TonightNeed(base: 480, debt: 0)
        let plan = TonightPlan(need: need, bedtime: 30, upBy: 510, clockShift: -60, plan: nil)
        XCTAssertEqual(plan.timeInBedAllowed, 540)
    }
}

final class Round3LabelTests: XCTestCase {
    // N4: one label set, and the effort target follows it.
    func testEffortFollowsRecoveryLevel() {
        XCTAssertEqual(Recovery.level(69, usual: 78), .steady)
        XCTAssertEqual(Recovery.label(69, usual: 78), "Take it steady")
        XCTAssertEqual(Recovery.level(69, usual: 78).effort, "Steady")
        XCTAssertEqual(Recovery.level(60, usual: 78).effort, "Go easy")
        XCTAssertEqual(Recovery.level(84, usual: 78).effort, "Push")
        XCTAssertEqual(Recovery.level(78, usual: 78).effort, "As planned")
        for score in 1...100 {
            XCTAssertEqual(Recovery.level(score, usual: 78, spread: 12).label, Recovery.label(score, usual: 78, spread: 12))
        }
    }

    // N14: the fixed middle stress band doesn't claim a personal baseline.
    func testStressMiddleBandIsNotCalledUsual() {
        XCTAssertEqual(StressModel.label(for: 30).rawValue, "Moderate")
    }

    // U7: the curve readout says where a level sits in today's range.
    func testEnergyRelativeCue() {
        let e = EnergyModel.day(.init(wake: 450, asleepMinutes: 450, sleepDebt: 0, habitualMidSleep: 270,
                                      habitualSleepOnset: 1470, wokeFromLightSleep: true, bedtime: 1470, sleepNeed: 470))
        let hi = e.curve.map(\.level).max()!, lo = e.curve.map(\.level).min()!
        XCTAssertEqual(e.relativeCue(level: hi), "today's peak")
        XCTAssertEqual(e.relativeCue(level: lo), "today's low")
        if hi.rounded() - lo.rounded() >= 6 {
            XCTAssertEqual(e.relativeCue(level: hi.rounded() - 3), "3 below today's peak")
        }
    }

    // F2: one peak for Energy's summary, chart and readout, even on a day
    // whose evening second wind tops the morning peak.
    func testEnergyDayPeakIsTheCurvesHighestPoint() {
        let e = EnergyModel.day(.init(wake: 497, asleepMinutes: 330, sleepDebt: 276, habitualMidSleep: 300,
                                      habitualSleepOnset: 1430, wokeFromLightSleep: true, bedtime: 1430, sleepNeed: 505))
        XCTAssertEqual(e.dayPeak.level, e.curve.map(\.level).max())
        XCTAssertGreaterThanOrEqual(e.dayPeak.level, e.highest.level)
        XCTAssertEqual(e.relativeCue(level: e.dayPeak.level), "today's peak")
    }
}

final class Round3CycleTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func days(_ start: Int, _ count: Int) -> [Date] {
        let d0 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
        return (0..<count).map { cal.date(byAdding: .day, value: start + $0, to: d0)! }
    }

    // N10: period length from her logged bleeding, not a fixed 5.
    func testPeriodLengthIsLearnedFromLoggedBleeding() {
        let bleeds = days(0, 6) + days(29, 6) + days(58, 7)
        XCTAssertEqual(CycleEstimator.periodLength(bleedDays: bleeds, calendar: cal), 6)
        XCTAssertNil(CycleEstimator.periodLength(bleedDays: [], calendar: cal))
        // One unlogged day in the middle is still one period.
        let gappy = days(0, 2) + days(3, 3)
        XCTAssertEqual(CycleEstimator.periodLength(bleedDays: gappy, calendar: cal), 6)
        // Day 6 of a 6-day period is the period, not follicular.
        XCTAssertEqual(CycleEstimator.phase(day: 6, length: 29, periodLength: 6), .period)
        XCTAssertEqual(CycleEstimator.phase(day: 6, length: 29), .follicular)
        let display = CycleDisplay.make(tracking: true, irregular: false, birthControl: nil, cycleDay: 6, cycleLength: 29, periodLength: 6)
        XCTAssertEqual(display, .phases(day: 6, length: 29, phase: .period))
    }
}

/// Women's health review (Okafor J, K, L, M).
final class CycleReviewTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private let d0 = Date(timeIntervalSince1970: 1_780_000_000)
    private func starts(_ gaps: [Int], from start: Date? = nil) -> [Date] {
        var out = [cal.startOfDay(for: start ?? d0)]
        for g in gaps { out.append(cal.date(byAdding: .day, value: g, to: out.last!)!) }
        return out
    }

    // J: ovulation about 13 days before the next period, a 3-day window around it.
    func testOvulationIsLengthMinus13() {
        XCTAssertEqual(CycleEstimator.ovulationDay(length: 29), 16)
        XCTAssertEqual(CycleEstimator.phase(day: 14, length: 29), .follicular)
        XCTAssertEqual(CycleEstimator.phase(day: 15, length: 29), .ovulation)
        XCTAssertEqual(CycleEstimator.phase(day: 17, length: 29), .ovulation)
        XCTAssertEqual(CycleEstimator.phase(day: 18, length: 29), .luteal)
        XCTAssertEqual(CycleEstimator.phase(day: 13, length: 28), .follicular)
        XCTAssertEqual(CycleEstimator.phase(day: 14, length: 28), .ovulation)
    }

    // K: late luteal is the last 7 days.
    func testLateLutealIsLastSevenDays() {
        XCTAssertFalse(CycleEstimator.isLateLuteal(day: 21, length: 28))
        XCTAssertTrue(CycleEstimator.isLateLuteal(day: 22, length: 28))
        XCTAssertTrue(CycleEstimator.isLateLuteal(day: 28, length: 28))
        XCTAssertEqual((1...35).filter { CycleEstimator.isLateLuteal(day: $0, length: 35) }.count, 7)
    }

    // M: the usual length ignores bleeds from before the last method change.
    func testUsualLengthOnlyFromCyclesSinceMethodChange() {
        // Two pill bleeds 28 days apart, then natural cycles of 33 days.
        let s = starts([28, 28, 33, 33, 34])
        XCTAssertEqual(CycleEstimator.lengths(periodStarts: s, calendar: cal).usual, 33)
        let change = s[2]
        let since = CycleEstimator.lengths(periodStarts: s, since: change, calendar: cal)
        XCTAssertEqual(since.gaps, [33, 33, 34])
        XCTAssertEqual(since.usual, 33)
        // One start since the change: no usual length yet.
        XCTAssertNil(CycleEstimator.lengths(periodStarts: s, since: s[5], calendar: cal).usual)
        // Only the most recent 12 cycles count.
        let many = starts(Array(repeating: 40, count: 5) + Array(repeating: 30, count: 12))
        XCTAssertEqual(CycleEstimator.lengths(periodStarts: many, calendar: cal).gaps.count, 12)
        XCTAssertEqual(CycleEstimator.lengths(periodStarts: many, calendar: cal).usual, 30)
    }

    // L: cycles under 21 or over 35 days, a wide spread, or few periods a year.
    func testCyclePatternFlags() {
        let regular = CycleEstimator.pattern(periodStarts: starts([28, 30, 29, 31]), ageYears: 20, now: d0, calendar: cal)
        XCTAssertFalse(regular.hasNote)
        XCTAssertEqual(regular.spread, 3)

        let oneLong = CycleEstimator.pattern(periodStarts: starts([28, 36, 29]), ageYears: 20, now: d0, calendar: cal)
        XCTAssertEqual(oneLong.outOfRange, 1)
        XCTAssertTrue(oneLong.hasNote)
        XCTAssertFalse(oneLong.worthMentioning)

        let twoShort = CycleEstimator.pattern(periodStarts: starts([19, 28, 20]), ageYears: 20, now: d0, calendar: cal)
        XCTAssertTrue(twoShort.worthMentioning)

        // A 10-day spread is wide at any age; 8 days only from 26 to 41.
        XCTAssertTrue(CycleEstimator.pattern(periodStarts: starts([24, 34, 30]), ageYears: 20, now: d0, calendar: cal).spreadIsWide)
        XCTAssertFalse(CycleEstimator.pattern(periodStarts: starts([25, 33, 30]), ageYears: 20, now: d0, calendar: cal).spreadIsWide)
        XCTAssertTrue(CycleEstimator.pattern(periodStarts: starts([25, 33, 30]), ageYears: 30, now: d0, calendar: cal).spreadIsWide)
        XCTAssertEqual(CycleEstimator.spreadLimit(ageYears: nil), 9)

        // A year of history with only 6 periods.
        let first = cal.date(byAdding: .day, value: -400, to: d0)!
        let sparse = CycleEstimator.pattern(periodStarts: starts([60, 60, 60, 60, 60, 60], from: first), ageYears: 20, now: d0, calendar: cal)
        XCTAssertTrue(sparse.fewPerYear)
        XCTAssertTrue(sparse.worthMentioning)
    }
}

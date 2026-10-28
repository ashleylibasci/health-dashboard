import XCTest
@testable import HealthCore

/// Tests for the fixes from test round 1 (finding IDs in each test name or comment).
private let newYork: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

final class WallClockTests: XCTestCase {
    // W16: Sun Nov 1 2026 the clocks fall back at 2am.
    func testFallBackMorningUsesTheWallClock() {
        let wakeDay = day(2026, 11, 1)
        XCTAssertEqual(Clock.minutes(day(2026, 11, 1, 8, 0), relativeTo: wakeDay, calendar: newYork), 480)
        XCTAssertEqual(Clock.minutes(day(2026, 10, 31, 23, 0), relativeTo: wakeDay, calendar: newYork), -60)
        XCTAssertEqual(Clock.minutes(day(2026, 11, 1, 0, 30), relativeTo: wakeDay, calendar: newYork), 30)
        let alarm = Clock.date(480, relativeTo: wakeDay, calendar: newYork)
        XCTAssertEqual(newYork.component(.hour, from: alarm), 8)
        XCTAssertEqual(newYork.component(.minute, from: alarm), 0)
        let bed = Clock.date(-60, relativeTo: wakeDay, calendar: newYork)
        XCTAssertEqual(newYork.component(.day, from: bed), 31)
        XCTAssertEqual(newYork.component(.hour, from: bed), 23)
    }

    func testSpringForwardAndRoundTrip() {
        let wakeDay = day(2026, 3, 8)
        XCTAssertEqual(Clock.minutes(day(2026, 3, 8, 8, 0), relativeTo: wakeDay, calendar: newYork), 480)
        // 2:30am doesn't exist that night; it moves forward, never back.
        let missing = Clock.date(150, relativeTo: wakeDay, calendar: newYork)
        XCTAssertEqual(newYork.component(.hour, from: missing), 3)
        let normal = day(2026, 10, 14)
        for m in [-300, -60, 0, 30, 502, 1439, 1470, 1600] {
            XCTAssertEqual(Clock.minutes(Clock.date(m, relativeTo: normal, calendar: newYork), relativeTo: normal, calendar: newYork), m)
        }
    }
}

final class CycleDisplayFixTests: XCTestCase {
    // W4: the method decides before PCOS/irregular.
    func testPillWinsOverPCOS() {
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: true, birthControl: .combinedPill, cycleDay: nil, cycleLength: 28, packDay: 9),
                       .pack(day: 9, activeDays: 21, packLength: 28))
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: true, birthControl: .implant, cycleDay: 12, cycleLength: 28), .suppressed(.implant))
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: true, birthControl: .hormonalIUD, cycleDay: 12, cycleLength: 28),
                       .irregular(daysSinceLastPeriod: 11))
    }

    // W2 / round 2 (Maya N1): a bleed date is never turned into a pack day
    // inside make(); only the pack day passed in counts. Placing a bleed in
    // the pack is one rule: activeDays + 3.
    func testNoPackDayFromTheBleed() {
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: false, birthControl: .ring, cycleDay: 22, cycleLength: 28),
                       .suppressed(.ring))
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: false, birthControl: .combinedPill, cycleDay: nil, cycleLength: 28),
                       .suppressed(.combinedPill))
        XCTAssertEqual(CycleDisplay.bleedStartPackDay(activeDays: 21, packLength: 28), 24)
        XCTAssertEqual(CycleDisplay.bleedStartPackDay(activeDays: 24, packLength: 28), 27)
        XCTAssertEqual(CycleDisplay.bleedStartPackDay(activeDays: 28, packLength: 28), 28)
    }

    func testPackSettingsAndContinuousUse() {
        let continuous = CycleDisplay.make(tracking: true, irregular: false, birthControl: .combinedPill, cycleDay: 2, cycleLength: 28,
                                           packDay: 26, activeDays: 28, packLength: 28)
        XCTAssertEqual(continuous, .pack(day: 26, activeDays: 28, packLength: 28))
        XCTAssertFalse(continuous.hasBreakWeek)
        XCTAssertFalse(continuous.isBreakWeek)
        XCTAssertNil(continuous.daysToBreak)

        let short = CycleDisplay.make(tracking: true, irregular: false, birthControl: .combinedPill, cycleDay: nil, cycleLength: 28,
                                      packDay: 25, activeDays: 24, packLength: 28)
        XCTAssertTrue(short.isBreakWeek)
        XCTAssertEqual(short.daysToBreak, 0)

        let normal = CycleDisplay.make(tracking: true, irregular: false, birthControl: .patch, cycleDay: nil, cycleLength: 28, packDay: 16)
        XCTAssertEqual(normal.daysToBreak, 6)
        // A stale pack day wraps into the pack instead of running past it.
        XCTAssertEqual(CycleDisplay.make(tracking: true, irregular: false, birthControl: .combinedPill, cycleDay: nil, cycleLength: 28, packDay: 30),
                       .pack(day: 2, activeDays: 21, packLength: 28))
    }

    // W3: past the usual length, overdue (no luteal, no wrap).
    func testOverdue() {
        let d = CycleDisplay.make(tracking: true, irregular: false, birthControl: nil, cycleDay: 35, cycleLength: 29)
        XCTAssertEqual(d, .overdue(day: 35, typicalLength: 29))
        XCTAssertFalse(d.isLateLuteal)
        let grace = CycleDisplay.make(tracking: true, irregular: false, birthControl: .copperIUD, cycleDay: 32, cycleLength: 29)
        if case .phases(32, 29, .luteal) = grace {} else { XCTFail("within 3 days of the usual length it's still luteal: \(grace)") }
    }
}

final class CaffeineFixTests: XCTestCase {
    func testHalfLifeIsUsed() {
        let dose = [CaffeineDose(time: 580, mg: 130)]
        // About one and a half times the half-life leaves about twice as much by midnight.
        XCTAssertEqual(CaffeineModel.estrogenHalfLifeHours, 8)
        XCTAssertGreaterThan(CaffeineModel.amount(at: 1470, doses: dose, halfLifeHours: 8),
                             CaffeineModel.amount(at: 1470, doses: dose) * 2)
        XCTAssertLessThan(CaffeineModel.cutoff(bedtime: 1470, halfLifeHours: 8), CaffeineModel.cutoff(bedtime: 1470))
    }

    func testDoseAwareBedtimeCheck() {
        XCTAssertTrue(CaffeineModel.tooMuchAtBedtime(doses: [CaffeineDose(time: 900, mg: 160)], bedtime: 1470))
        XCTAssertFalse(CaffeineModel.tooMuchAtBedtime(doses: [CaffeineDose(time: 840, mg: 64)], bedtime: 1470))
        XCTAssertTrue(CaffeineModel.wouldBeTooMuch(adding: CaffeineDose(time: 840, mg: 64), to: [CaffeineDose(time: 840, mg: 64)],
                                                   bedtime: 1470, halfLifeHours: 8))

        let latest = try! XCTUnwrap(CaffeineModel.latestTime(forMg: 160, bedtime: 1470))
        XCTAssertLessThan(CaffeineModel.amount(at: 1470, doses: [CaffeineDose(time: latest, mg: 160)]), 25)
        XCTAssertGreaterThan(CaffeineModel.amount(at: 1470, doses: [CaffeineDose(time: latest + 15, mg: 160)]), 25)
        // A bigger drink has to come earlier; with the pill's half-life, earlier still.
        XCTAssertLessThan(latest, try! XCTUnwrap(CaffeineModel.latestTime(forMg: 64, bedtime: 1470)))
        XCTAssertLessThan(try! XCTUnwrap(CaffeineModel.latestTime(forMg: 160, bedtime: 1470, halfLifeHours: 8)), latest)
        // Already over the allowance: nothing more fits.
        XCTAssertNil(CaffeineModel.latestTime(forMg: 64, bedtime: 1470, existing: [CaffeineDose(time: 1200, mg: 200)]))
    }

    func testLateWakeWindowIsNeverInverted() {
        let e = EnergyModel.day(.init(wake: 780, asleepMinutes: 460, sleepDebt: 0, habitualMidSleep: 262, habitualSleepOnset: 1482, bedtime: 1470))
        let t = CaffeineModel.timing(energy: e, cutoff: 780, firstDrinkAt: nil)
        XCTAssertGreaterThanOrEqual(t.bestWindow.end, t.bestWindow.start)
    }
}

final class EnergyFixTests: XCTestCase {
    func input(wake: Minutes = 480, asleep: Int = 460, debt: Int = 0, light: Bool = true, bed: Minutes = 1470) -> EnergyModel.Input {
        .init(wake: wake, asleepMinutes: asleep, sleepDebt: debt, habitualMidSleep: 262, habitualSleepOnset: 1482, wokeFromLightSleep: light, bedtime: bed)
    }

    // W8: the score covers a fixed 16h from wake, so bedtime can't move it…
    func testScoreIgnoresBedtime() {
        XCTAssertEqual(EnergyModel.day(input(bed: 1380)).score, EnergyModel.day(input(bed: 1560)).score)
    }

    // …and a very late wake doesn't score higher than a usual one.
    func testLateWakeDoesNotInflateTheScore() {
        XCTAssertLessThan(EnergyModel.day(input(wake: 780)).score, EnergyModel.day(input(wake: 480)).score)
    }

    func testZoneNamesAndOrderAfterALateWake() {
        let e = EnergyModel.day(input(wake: 780))
        let peak = try! XCTUnwrap(e.zone(.morningPeak)), dip = try! XCTUnwrap(e.zone(.afternoonDip)), second = try! XCTUnwrap(e.zone(.secondWind))
        XCTAssertEqual(peak.title, "First peak")
        XCTAssertGreaterThanOrEqual(peak.range.start, try! XCTUnwrap(e.zone(.grogginess)).range.end)
        XCTAssertLessThan(peak.range.end, dip.range.start)
        XCTAssertLessThan(dip.range.end, second.range.start)
        XCTAssertEqual(EnergyModel.day(input(wake: 450)).zone(.morningPeak)?.title, "Morning peak")
    }

    func testDriversComeFromTheModel() {
        let neutral = EnergyModel.drivers(input(wake: 262 + 235, asleep: 470), need: 470)
        XCTAssertTrue(neutral.isEmpty, "\(neutral)")
        let bad = EnergyModel.drivers(input(wake: 441, asleep: 400, debt: 160, light: false), need: 470)
        let debt = try! XCTUnwrap(bad.first { $0.kind == .sleepDebt })
        XCTAssertLessThan(debt.points, 0)
        XCTAssertEqual(debt.amount, 160)
        XCTAssertLessThan(try! XCTUnwrap(bad.first { $0.kind == .wokeFromDeepSleep }).points, 0)
        XCTAssertLessThan(try! XCTUnwrap(bad.first { $0.kind == .lastNight }).points, 0)
        XCTAssertEqual(bad.map { abs($0.points) }, bad.map { abs($0.points) }.sorted(by: >))
        XCTAssertEqual(EnergyModel.day(input()).input, input())
    }

    // W1: the bank stays 0–100.
    func testBankIsClamped() {
        XCTAssertEqual(EnergyBank.level(atWake: 90, hoursAwake: -6), 90)
        XCTAssertEqual(EnergyBank.level(atWake: 120, hoursAwake: 0), 100)
        XCTAssertEqual(EnergyBank.level(atWake: 60, hoursAwake: 40), 0)
    }
}

final class BodySignalFixTests: XCTestCase {
    // W10: sleep and workouts without steps are left out.
    func testStressLeavesOutSleepAndWorkouts() {
        var samples = (0...6).map { StressModel.Sample(hour: $0, heartRate: 58, hrv: 60, steps: 0, asleep: true) }
        samples += (8...12).map { StressModel.Sample(hour: $0, heartRate: 80, hrv: 35, steps: 100) }
        samples.append(StressModel.Sample(hour: 13, heartRate: 150, hrv: 15, steps: 40, activeKcal: 320))   // swim
        let day = StressModel.day(samples, restingHR: 60, baselineHRV: 50)
        XCTAssertEqual(day.countedHours, 5)
        XCTAssertNil(day.hours.first { $0.hour == 3 }!.level)
        XCTAssertTrue(day.hours.first { $0.hour == 3 }!.asleep)
        XCTAssertTrue(day.hours.first { $0.hour == 13 }!.active)
        XCTAssertNotEqual(day.peak?.hour, 13)
        XCTAssertEqual(day.label, StressModel.label(for: day.average!))
        XCTAssertEqual(StressDay.Label.allCases.map(\.rawValue), ["Low", "Moderate", "Raised", "High"])
    }

    // W11: training and luteal context; likelihood labels.
    func testIllnessContext() {
        func c(training: Bool = false, luteal: Bool = false) -> IllnessSignal.Confidence {
            IllnessSignal.evaluate(restingHRDelta: 5, hrvDeltaPct: -18, respiratoryRateDelta: nil, wristTempDelta: nil,
                                   lutealPhase: luteal, hardTrainingYesterday: training).confidence
        }
        XCTAssertEqual(c(), .medium)
        XCTAssertEqual(c(training: true), .none)
        XCTAssertEqual(c(luteal: true), .none)
        let s = IllnessSignal.evaluate(restingHRDelta: 5, hrvDeltaPct: -18, respiratoryRateDelta: nil, wristTempDelta: nil,
                                       lutealPhase: false, hardTrainingYesterday: true)
        XCTAssertEqual(s.factors.first?.note, "Expected after yesterday's hard training")
        XCTAssertEqual(IllnessSignal.Confidence.allCases.map(\.rawValue), ["All clear", "Unlikely", "Possible", "Likely"])
        // Real illness still shows through.
        XCTAssertEqual(IllnessSignal.evaluate(restingHRDelta: 9, hrvDeltaPct: -30, respiratoryRateDelta: 1.5, wristTempDelta: 0.8,
                                              lutealPhase: true, hardTrainingYesterday: true).confidence, .high)
    }

    // W12
    func testFitnessAge() {
        XCTAssertEqual(FitnessAge.estimate(vo2Max: 45, sex: .female), 20)
        XCTAssertTrue(FitnessAge.isTopOfChart(vo2Max: 45, sex: .female))
        XCTAssertFalse(FitnessAge.isTopOfChart(vo2Max: 38.2, sex: .female))
        XCTAssertEqual(FitnessAge.level(vo2Max: 38, sex: .female, age: 20), "Below average for your age")
        // Round 2: banded by the same years as the fitness age (13 years younger).
        XCTAssertEqual(FitnessAge.level(vo2Max: 38, sex: .female, age: 40), "Well above average for your age")
        XCTAssertEqual(FitnessAge.level(vo2Max: 40, sex: .female, age: nil), "About average for a 20-year-old")
    }
}

final class SleepFixTests: XCTestCase {
    // W7
    func testDebtIsARealSum() {
        XCTAssertEqual(SleepDebt.minutes(need: 480, lastNightsNewestFirst: [450, 450, 450]), 90)
        XCTAssertEqual(SleepDebt.minutes(need: 480, lastNightsNewestFirst: Array(repeating: 470, count: 14)), 140)
        let w = SleepDebt.weights(count: 14)
        XCTAssertEqual(w.reduce(0, +), 14, accuracy: 1e-9)
        XCTAssertLessThan(w[0], 1.5)
        XCTAssertGreaterThan(w[0], w[13])
        // One bad night alone is about 1.4× its shortfall, not 2×.
        let one = SleepDebt.minutes(need: 480, lastNightsNewestFirst: [360] + Array(repeating: 480, count: 13))
        XCTAssertLessThan(one, 180)
        XCTAssertGreaterThan(one, 120)
    }

    func testMetNeedThreshold() {
        XCTAssertTrue(SleepNeedEstimator.metNeed(asleep: 455, need: 470))
        XCTAssertFalse(SleepNeedEstimator.metNeed(asleep: 454, need: 470))
    }

    // W19: a normal two-night weekend counts toward the rebound.
    func testReboundFromWeekends() {
        let d0 = day(2026, 9, 5)   // a Saturday
        var nights: [NightRecord] = []
        for week in 0..<3 {
            for (i, m) in [(0, 540), (1, 492)] {
                let wake = newYork.date(byAdding: .day, value: week * 7 + i, to: d0)!
                nights.append(NightRecord(wakeDay: wake, bedtime: 60, sleepOnset: 70, wake: 70 + m, asleepMinutes: m, alarmUsed: false))
            }
            let monday = newYork.date(byAdding: .day, value: week * 7 + 2, to: d0)!
            nights.append(NightRecord(wakeDay: monday, bedtime: 30, sleepOnset: 40, wake: 440, asleepMinutes: 400, alarmUsed: true))
        }
        let r = try! XCTUnwrap(SleepNeedEstimator.reboundEstimate(nights, calendar: newYork))
        XCTAssertEqual(r.minutes, 492)
        XCTAssertEqual(r.samples, 3)
    }
}

final class PairingAndStreakTests: XCTestCase {
    // W19: one drink, one night.
    func testAlcoholEveningWindow() {
        let sat = day(2026, 10, 10), sun = day(2026, 10, 11)
        let w = NightPairing.alcoholWindow(wakeDay: sun, calendar: newYork)
        XCTAssertEqual(w.start, day(2026, 10, 10, 17))
        XCTAssertEqual(w.end, day(2026, 10, 11, 5))
        let oneAM = day(2026, 10, 11, 1)
        XCTAssertTrue(w.contains(oneAM))
        XCTAssertFalse(NightPairing.alcoholWindow(wakeDay: newYork.date(byAdding: .day, value: 1, to: sun)!, calendar: newYork).contains(oneAM))
        XCTAssertFalse(NightPairing.alcoholWindow(wakeDay: sat, calendar: newYork).contains(oneAM))
        XCTAssertFalse(w.contains(day(2026, 10, 10, 13)))   // lunch isn't the evening
    }

    // W19: caffeine pairs with the sleep that follows; after midnight is late.
    func testCaffeinePairsWithTheFollowingSleep() {
        let wake = day(2026, 10, 15)
        let drinks = [day(2026, 10, 14, 9, 30), day(2026, 10, 15, 0, 20), day(2026, 10, 15, 9, 0)]
        let last = NightPairing.lastCaffeine(drinks: drinks, wakeDay: wake, sleepOnset: 60, calendar: newYork)
        XCTAssertEqual(last, 1460)   // 12:20am, counted on the evening before
        let test = CaffeineCutoffTest.make(lastCaffeineByNight: [(last, 400), (600, 470), (nil, 480)])
        XCTAssertEqual(test.groups.first { $0.label == "After 3pm" }?.averageAsleep, 400)
        XCTAssertEqual(test.groups.first { $0.label == "No caffeine" }?.nights, 1)
        XCTAssertEqual(test.groups.first { $0.label == "Before 12pm" }?.nights, 1)
        // A drink after she fell asleep belongs to the next night.
        XCTAssertNil(NightPairing.lastCaffeine(drinks: [day(2026, 10, 15, 1, 30)], wakeDay: wake, sleepOnset: 60, calendar: newYork))
    }

    func testLateIsRelativeToHerUsualBedtime() {
        XCTAssertEqual(LateNights.threshold(bedtimes: [60, 70, 80, 90, 100, 60, 75]), 165)
        XCTAssertEqual(LateNights.threshold(bedtimes: [-60, -30]), 120)
    }

    // W25
    func testCalendarAwareStreaks() {
        let today = day(2026, 10, 20, 9)
        func d(_ back: Int) -> Date { newYork.startOfDay(for: newYork.date(byAdding: .day, value: -back, to: today)!) }
        // Recorded and met: yesterday and the three days before; a gap at 5 days back.
        let days = [1, 2, 3, 4, 6, 7].map(d)
        let met = Set(days)
        XCTAssertEqual(Streaks.current(days: days, matching: met, today: today, todayPending: true, calendar: newYork), 4)
        XCTAssertEqual(Streaks.current(days: days, matching: met, today: today, todayPending: false, calendar: newYork), 0)
        XCTAssertEqual(Streaks.current(days: days + [d(0)], matching: met.union([d(0)]), today: today, todayPending: false, calendar: newYork), 5)
        // A recorded day that missed the goal ends it.
        XCTAssertEqual(Streaks.current(days: days, matching: met.subtracting([d(2)]), today: today, todayPending: true, calendar: newYork), 1)
        XCTAssertEqual(Streaks.longest(matching: met, calendar: newYork), 4)
    }
}

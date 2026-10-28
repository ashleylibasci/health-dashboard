import XCTest
@testable import HealthCore

/// Round 4 (women's health review): heart, recovery, stress, sick check,
/// fitness age and training days.
final class Round4HeartTests: XCTestCase {

    // Brandt F4: a natural cycle's own shift is taken out of recovery; none
    // on methods that stop ovulation.
    func testCycleHeartShift() {
        XCTAssertEqual(CycleHeartShift.forDay(3, length: 29), .period)
        XCTAssertEqual(CycleHeartShift.forDay(7, length: 29), .period)
        XCTAssertEqual(CycleHeartShift.forDay(10, length: 29), .none)
        XCTAssertEqual(CycleHeartShift.forDay(22, length: 29), .luteal)
        XCTAssertEqual(CycleHeartShift.forDay(31, length: 29), .none)        // past her usual length
        XCTAssertEqual(CycleHeartShift.luteal.restingHR, 1.5)
        XCTAssertEqual(CycleHeartShift.luteal.hrvPct, -4)
        XCTAssertEqual(CycleHeartShift.period.restingHR, -1.5)
        XCTAssertEqual(CycleHeartShift.period.hrvPct, 4)

        let natural = CycleDisplay.make(tracking: true, irregular: false, birthControl: nil, cycleDay: 22, cycleLength: 29)
        XCTAssertEqual(CycleHeartShift.make(natural), .luteal)
        let pill = CycleDisplay.make(tracking: true, irregular: false, birthControl: .combinedPill, cycleDay: 22, cycleLength: 29,
                                     packDay: 3, activeDays: 21, packLength: 28)
        XCTAssertEqual(CycleHeartShift.make(pill), .none)
        for bc in [BirthControl.implant, .shot, .ring, .patch] {
            let d = CycleDisplay.make(tracking: true, irregular: false, birthControl: bc, cycleDay: 22, cycleLength: 29)
            XCTAssertEqual(CycleHeartShift.make(d), .none, bc.rawValue)
        }
        let overdue = CycleDisplay.make(tracking: true, irregular: false, birthControl: nil, cycleDay: 40, cycleLength: 29)
        XCTAssertEqual(CycleHeartShift.make(overdue), .none)
    }

    func testRecoveryAllowsForTheCycle() {
        // Luteal: +1.5 bpm and −4% HRV is exactly what's expected, so the score is the usual.
        XCTAssertEqual(Recovery.score(hrvDeltaPct: -4, restingHRDelta: 1.5, sleepShortfall: 0, cycle: .luteal), 78)
        XCTAssertLessThan(Recovery.score(hrvDeltaPct: -4, restingHRDelta: 1.5, sleepShortfall: 0), 78)
        // Period week: a low resting heart rate isn't extra credit.
        XCTAssertEqual(Recovery.score(hrvDeltaPct: 4, restingHRDelta: -1.5, sleepShortfall: 0, cycle: .period), 78)
        // No shift, no change.
        XCTAssertEqual(Recovery.score(hrvDeltaPct: -10, restingHRDelta: 2, sleepShortfall: 30, cycle: .none),
                       Recovery.score(hrvDeltaPct: -10, restingHRDelta: 2, sleepShortfall: 30))
    }

    // Brandt F8–F10: one resting-HR cutoff, HRV against her own spread, dials on her own range.
    func testHeartBands() {
        XCTAssertEqual(HeartBands.restingHR(delta: 3), .above)
        XCTAssertEqual(HeartBands.restingHR(delta: 2.9), .usual)
        XCTAssertEqual(HeartBands.restingHR(delta: -2), .below)
        XCTAssertEqual(HeartBands.hrv(deltaPct: -12), .wellBelow)
        XCTAssertEqual(HeartBands.hrv(deltaPct: -5), .below)
        XCTAssertEqual(HeartBands.hrv(deltaPct: 6), .above)
        // A jumpy HRV (spread 20%): −12% is an ordinary morning for her.
        XCTAssertEqual(HeartBands.hrv(deltaPct: -12, spreadPct: 20), .below)
        XCTAssertEqual(HeartBands.hrv(deltaPct: -8, spreadPct: 20), .usual)
        XCTAssertEqual(HeartBands.hrv(deltaPct: -21, spreadPct: 20), .wellBelow)

        XCTAssertNil(HeartBands.spread([1, 2, 3]))
        XCTAssertNil(HeartBands.usualRange([50, 50, 50, 50, 50, 50, 50, 50, 50, 50]))
        let r = HeartBands.usualRange((1...11).map(Double.init))!
        XCTAssertEqual(r.lowerBound, 2, accuracy: 0.001)
        XCTAssertEqual(r.upperBound, 10, accuracy: 0.001)
        XCTAssertEqual(HeartBands.gaugeFraction(2, range: r), 0.1, accuracy: 0.001)
        XCTAssertEqual(HeartBands.gaugeFraction(10, range: r), 0.9, accuracy: 0.001)
        XCTAssertEqual(HeartBands.gaugeFraction(-50, range: r), 0.03, accuracy: 0.001)
    }

    // Brandt F5, Laurent F3, Ruiz F5/F6: her own still-hour baseline, the
    // luteal allowance and an active hour scaled to her weight.
    func testStressBaselineAndLuteal() {
        XCTAssertNil(StressModel.stillBaseline(heartRates: Array(repeating: 70, count: 10)))
        let still = StressModel.stillBaseline(heartRates: (0..<40).map { 68 + Double($0 % 5) })!
        XCTAssertEqual(still.median, 70)
        XCTAssertEqual(still.spread, 4)                      // floored
        // 82 bpm is 12 above her still median: three spreads, the top.
        let day = StressModel.day([.init(hour: 10, heartRate: 82, hrv: nil, steps: 0)], restingHR: 60, baselineHRV: 0, still: still)
        XCTAssertEqual(day.hours.first?.level, 100)
        // Luteal takes 2 bpm off.
        let luteal = StressModel.day([.init(hour: 10, heartRate: 76, hrv: nil, steps: 0)], restingHR: 60, baselineHRV: 0, still: still, luteal: true)
        XCTAssertEqual(luteal.hours.first?.level, 33)
        // Fallback formula (no still baseline): 70 vs resting 60 is 40; luteal 32.
        let plain = StressModel.day([.init(hour: 10, heartRate: 70, hrv: nil, steps: 0)], restingHR: 60, baselineHRV: 0)
        XCTAssertEqual(plain.hours.first?.level, 40)
        let plainLuteal = StressModel.day([.init(hour: 10, heartRate: 70, hrv: nil, steps: 0)], restingHR: 60, baselineHRV: 0, luteal: true)
        XCTAssertEqual(plainLuteal.hours.first?.level, 32)

        XCTAssertEqual(StressModel.activeKcal(bodyMassKg: nil), 60)
        XCTAssertEqual(StressModel.activeKcal(bodyMassKg: 52), 52)
        XCTAssertEqual(StressModel.activeKcal(bodyMassKg: 30), 45)
        // A 52 kg woman's 55 kcal hour counts as active.
        let light = StressModel.day([.init(hour: 10, heartRate: 90, hrv: nil, steps: 100, activeKcal: 55)], restingHR: 60, baselineHRV: 0,
                                    activeKcal: StressModel.activeKcal(bodyMassKg: 52))
        XCTAssertTrue(light.hours.first?.active ?? false)
    }

    func testHardTrainingScalesWithWeight() {
        // 8 kcal/kg without history: 400 kcal for 50 kg, 640 for 80 kg.
        XCTAssertTrue(IllnessSignal.isHardTraining(yesterdayKcal: 420, earlierDaysKcal: [], bodyMassKg: 50))
        XCTAssertFalse(IllnessSignal.isHardTraining(yesterdayKcal: 600, earlierDaysKcal: [], bodyMassKg: 80))
        // With history the floor is 5 kcal/kg.
        let light = Array(repeating: 120.0, count: 10)
        XCTAssertTrue(IllnessSignal.isHardTraining(yesterdayKcal: 260, earlierDaysKcal: light, bodyMassKg: 50))
        XCTAssertFalse(IllnessSignal.isHardTraining(yesterdayKcal: 260, earlierDaysKcal: light, bodyMassKg: 70))
    }

    // Brandt F6: cutoffs scale with her own spread and drop a little in her period week.
    func testSickCutoffsScale() {
        func c(_ rhr: Double, _ hrv: Double, period: Bool = false, rhrSD: Double? = nil, hrvSD: Double? = nil) -> IllnessSignal {
            IllnessSignal.evaluate(restingHRDelta: rhr, hrvDeltaPct: hrv, respiratoryRateDelta: nil, wristTempDelta: nil,
                                   lutealPhase: false, periodDay: period, restingHRSpread: rhrSD, hrvSpreadPct: hrvSD)
        }
        XCTAssertTrue(c(4, 0).factors[0].flagged)
        // A jumpy resting heart rate (spread 3 bpm): +4 isn't enough, +6 is.
        XCTAssertFalse(c(4, 0, rhrSD: 3).factors[0].flagged)
        XCTAssertTrue(c(6, 0, rhrSD: 3).factors[0].flagged)
        // HRV spread 14%: −15% isn't enough, −21% is.
        XCTAssertFalse(c(0, -15, hrvSD: 14).factors[1].flagged)
        XCTAssertTrue(c(0, -21, hrvSD: 14).factors[1].flagged)
        // Period week: +3 bpm and −12% count.
        XCTAssertTrue(c(3, 0, period: true).factors[0].flagged)
        XCTAssertTrue(c(0, -12, period: true).factors[1].flagged)
        XCTAssertFalse(c(3, -12).factors[0].flagged)
    }

    // Brandt F1–F3, Liu 2: FRIEND 2015 women's medians, a range, wide bands.
    func testFitnessAgeOnFriendWomen() {
        XCTAssertEqual(FitnessAge.average(age: 20), 37.6)
        XCTAssertEqual(FitnessAge.average(age: 25), 37.6)
        XCTAssertEqual(FitnessAge.average(age: 35), 30.2)
        XCTAssertEqual(FitnessAge.average(age: 75), 18.3)
        XCTAssertEqual(FitnessAge.average(age: 30), 33.9, accuracy: 0.001)
        XCTAssertEqual(FitnessAge.estimate(vo2Max: 26.7), 45)
        XCTAssertEqual(FitnessAge.estimate(vo2Max: 20.0), 65)
        XCTAssertEqual(FitnessAge.estimate(vo2Max: 10), 90)
        // ±5 points of Watch error as a range.
        XCTAssertEqual(FitnessAge.range(vo2Max: 30.2), 28...50)
        XCTAssertEqual(FitnessAge.rangeText(vo2Max: 30.2), "28\u{2013}50")
        XCTAssertEqual(FitnessAge.rangeText(vo2Max: 36), "Under 34")
        XCTAssertEqual(FitnessAge.rangeText(vo2Max: 44), "Under 25")
        // Bands: the middle half of women her decade is "About average".
        XCTAssertEqual(FitnessAge.level(vo2Max: 30, age: 22), "Below average for women in their 20s")
        XCTAssertEqual(FitnessAge.level(vo2Max: 31, age: 22), "About average for women in their 20s")
        XCTAssertEqual(FitnessAge.level(vo2Max: 45, age: 29), "Above average for women in their 20s")
        XCTAssertEqual(FitnessAge.level(vo2Max: 38, age: 17), "About average compared with women in their 20s")
        XCTAssertEqual(FitnessAge.level(vo2Max: 18, age: 85), "About average for women in their 70s")
    }
}

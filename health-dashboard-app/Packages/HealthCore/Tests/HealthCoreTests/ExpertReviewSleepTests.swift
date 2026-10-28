import XCTest
@testable import HealthCore

/// The sleep and energy fixes from the women's health expert review.
final class ExpertReviewSleepTests: XCTestCase {
    // Liu 10: when no wake window clearly beats the rest, there's no best window.
    func testNoClearBestWindowWhenMorningsAreAlike() {
        var rng = SeededRandom(seed: 3)
        let mornings = (0..<40).map { _ in
            Morning(wake: 400 + Int(rng.next() * 200), wokeFromLightSleep: nil, outcome: 3 + (rng.next() - 0.5) * 0.6)
        }
        XCTAssertNil(WakeHistory.analyze(mornings).bestWindow)
    }

    // Park 5: sleep debt deepens the body clock's dip and leaves its peaks.
    func testDebtDeepensDipsOnly() {
        let mid = 262                                  // 4:22am
        let dip = mid + 12 * 60, peak = mid + 6 * 60   // the 12h trough and crest
        XCTAssertLessThan(EnergyModel.circadian(dip, midSleep: mid, sleepDebt: 300),
                          EnergyModel.circadian(dip, midSleep: mid, sleepDebt: 0))
        XCTAssertEqual(EnergyModel.circadian(peak, midSleep: mid, sleepDebt: 300),
                       EnergyModel.circadian(peak, midSleep: mid, sleepDebt: 0), accuracy: 1e-9)
    }

    // Park 6: wind-down starts about 2 hours before usual sleep onset.
    func testWindDownStartsTwoHoursBeforeOnset() {
        let e = EnergyModel.day(.init(wake: 480, asleepMinutes: 460, sleepDebt: 0, habitualMidSleep: 262, habitualSleepOnset: 1482, bedtime: 1470))
        XCTAssertEqual(e.zone(.windDown)?.range, TimeRange(1365, 1425))
        XCTAssertEqual(e.zone(.melatonin)?.title, "Sleep window")
    }

    // Park 12: grogginess lasts about 30 minutes after a light-sleep wake,
    // about an hour after deep sleep.
    func testGrogginessLengths() {
        func groggy(light: Bool) -> Int? {
            EnergyModel.day(.init(wake: 480, asleepMinutes: 460, sleepDebt: 0, habitualMidSleep: 262, habitualSleepOnset: 1482,
                                  wokeFromLightSleep: light, bedtime: 1470)).zone(.grogginess)?.range.length
        }
        XCTAssertEqual(groggy(light: true), ExamPlanner.grogginessMinutes)
        XCTAssertEqual(groggy(light: false), ExamPlanner.grogginessMinutesDeep)
    }
}

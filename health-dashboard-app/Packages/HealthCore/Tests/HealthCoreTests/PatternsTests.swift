import XCTest
@testable import HealthCore

/// Saved-ideas build (Oct 29): Patterns (D-P2).
final class PatternsTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func night(_ i: Int, asleep: Int = 450, hrv: Double? = 0, rhr: Double? = 0, checkIn: Double? = nil,
                       latency: Int = 15) -> NightRecord {
        NightRecord(wakeDay: Date(timeIntervalSince1970: Double(i) * 86_400), bedtime: 30, sleepOnset: 30 + latency,
                    wake: 30 + latency + asleep, asleepMinutes: asleep,
                    outcome: NextDayOutcome(hrvDeltaPct: hrv, restingHRDelta: rhr, checkIn: checkIn))
    }

    // D-P2: 20 nights, 5 a side, and a difference past twice the wobble
    // and the measure's minimum.
    func testPatternComparisonGates() {
        // A clear 10-point drop with a small wobble.
        let with = [-12.0, -10, -9, -11, -8, -10]
        let without = (0..<15).map { Double($0 % 5) - 2 }       // −2…2, mean 0
        let c = PatternComparison.make(with: with, without: without, minimumSize: PatternMetric.hrv.minimumSize)
        XCTAssertTrue(c.enoughNights)
        XCTAssertEqual(c.difference ?? 0, -10, accuracy: 0.01)
        XCTAssertTrue(c.shows)
        // 19 nights: not yet.
        XCTAssertFalse(PatternComparison.make(with: with, without: Array(without.prefix(13)), minimumSize: 5).shows)
        // 4 on one side: not yet, however big.
        XCTAssertFalse(PatternComparison.make(with: Array(with.prefix(4)), without: without + [0, 0], minimumSize: 5).shows)
        // Inside the wobble: a 5-point difference between very noisy nights.
        let noisyWith = [-30.0, 20, -25, 15, -20, 10]
        let noisyWithout = (0..<14).map { $0 % 2 == 0 ? 25.0 : -25 }
        let n = PatternComparison.make(with: noisyWith, without: noisyWithout, minimumSize: 5)
        XCTAssertTrue(n.enoughNights)
        XCTAssertFalse(n.shows)
        // Past the wobble but under the minimum (2 minutes of sleep).
        let tiny = PatternComparison.make(with: Array(repeating: 448, count: 6) + [449],
                                          without: Array(repeating: 450, count: 13) + [451], minimumSize: PatternMetric.asleep.minimumSize)
        XCTAssertFalse(tiny.shows)
    }

    // D-P2: the clearest measure wins; nights without a known flag are left out.
    func testPatternFindPicksClearestMeasure() {
        var nights: [NightRecord] = []
        for i in 0..<30 {
            let flagged = i % 4 == 0                              // 8 nights
            nights.append(night(i, asleep: flagged ? 400 + i % 3 : 450 + i % 3, hrv: Double(i % 7) - 3, rhr: 0))
        }
        let p = Pattern.find(nights, metrics: [.hrv, .asleep]) { n in
            let i = Int(n.wakeDay.timeIntervalSince1970 / 86_400)
            return i == 29 ? nil : i % 4 == 0
        }
        XCTAssertEqual(p?.metric, .asleep)
        XCTAssertEqual(p?.comparison.nights, 29)
        XCTAssertEqual(p?.sentence(context: "On late-study nights"),
                       "On late-study nights, you slept 50\u{00A0}min less than on other nights.")
        // Not enough flagged nights: still a pattern to count from, no sentence.
        let few = Pattern.find(nights, metrics: [.hrv, .asleep]) { n in Int(n.wakeDay.timeIntervalSince1970 / 86_400) < 3 }
        XCTAssertEqual(few?.comparison.withCount, 3)
        XCTAssertNil(few?.sentence(context: "x"))
    }

    func testPatternPhrases() {
        XCTAssertEqual(PatternMetric.hrv.phrase(-9.2), "your HRV averaged 9% lower")
        XCTAssertEqual(PatternMetric.restingHR.phrase(3.4), "your resting heart rate averaged 3 bpm higher")
        XCTAssertEqual(PatternMetric.asleep.phrase(-70), "you slept 1h\u{00A0}10m less")
        XCTAssertEqual(PatternMetric.fallAsleep.phrase(12), "you took 12\u{00A0}min longer to fall asleep")
        XCTAssertEqual(PatternMetric.checkIn.phrase(-0.84), "you rated your mornings 0.8 lower out of 5")
        // Time to fall asleep is capped at 3 hours, as in H-E4.
        XCTAssertEqual(PatternMetric.fallAsleep.value(night(0, latency: 400)), 180)
    }

    // Weekend confound: free mornings sleep longer, parties fall on free
    // mornings. Compared within alarm and free mornings, the parties don't
    // get the weekend's longer sleep.
    private func week(_ count: Int, party: (Int, Bool) -> Bool, effect: Int = 0) -> [(NightRecord, Bool)] {
        (0..<count).map { i in
            let free = i % 7 >= 5
            let p = party(i, free)
            var n = night(i, asleep: (free ? 520 : 430) + (i * 7) % 11 - 5 + (p ? effect : 0))
            n.alarmUsed = !free
            return (n, p)
        }
    }

    func testPartiesOnWeekendsShowNoSleepPattern() {
        // Every Saturday and Sunday is a party: no party on an alarm morning.
        let data = week(70) { _, free in free }
        let flags = Dictionary(uniqueKeysWithValues: data.map { ($0.0.wakeDay, $0.1) })
        let plain = Pattern.find(data.map(\.0), metrics: [.asleep]) { flags[$0.wakeDay] }
        XCTAssertNotNil(plain?.sentence(context: "x"))          // what the confound would have shown
        let within = Pattern.find(data.map(\.0), metrics: [.asleep], withinAlarmMornings: true) { flags[$0.wakeDay] }
        XCTAssertNil(within?.sentence(context: "x"))
        XCTAssertEqual(within?.comparison.strataQualify, false)
        XCTAssertEqual(within?.strata?.first?.withCount, 0)
    }

    func testMostlyWeekendPartiesWithoutEffectShowNothing() {
        // Parties on most free mornings and some alarm mornings, no effect of
        // their own: both strata qualify and the pooled difference is ~0.
        let data = week(84) { i, free in free ? i % 7 == 5 || i % 14 == 6 : i % 7 == 4 }
        let flags = Dictionary(uniqueKeysWithValues: data.map { ($0.0.wakeDay, $0.1) })
        let plain = Pattern.find(data.map(\.0), metrics: [.asleep]) { flags[$0.wakeDay] }
        XCTAssertNotNil(plain?.sentence(context: "x"))
        let within = Pattern.find(data.map(\.0), metrics: [.asleep], withinAlarmMornings: true) { flags[$0.wakeDay] }
        XCTAssertEqual(within?.comparison.strataQualify, true)
        XCTAssertNil(within?.sentence(context: "x"))
    }

    func testPartiesOnBothKindsOfMorningsStillShowARealDifference() {
        let data = week(84, party: { i, free in free ? i % 7 == 5 : i % 7 == 4 }, effect: -40)
        let flags = Dictionary(uniqueKeysWithValues: data.map { ($0.0.wakeDay, $0.1) })
        let within = Pattern.find(data.map(\.0), metrics: [.asleep], withinAlarmMornings: true) { flags[$0.wakeDay] }
        XCTAssertEqual(within?.comparison.strataQualify, true)
        XCTAssertEqual(within?.comparison.difference ?? 0, -40, accuracy: 4)
        XCTAssertNotNil(within?.sentence(context: "On nights after a party"))
    }
}

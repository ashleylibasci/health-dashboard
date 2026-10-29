import XCTest
@testable import HealthCore

/// H-E2: pack-day baselines.
final class PackHeartShiftTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    private var packs: PackCalendar {
        PackCalendar(start: cal.date(from: DateComponents(year: 2026, month: 10, day: 11))!, activeDays: 21, packLength: 28)
    }

    private func series(_ value: (Int, Int) -> Double) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for pack in -3 ... -1 { for d in 1...28 { out[packs.date(pack: pack, day: d, calendar: cal)] = value(pack, d) } }
        return out
    }

    func testABreakWeekRiseInEveryPackCounts() {
        let rhr = series { _, d in d > 21 ? 1.2 : 0 }
        let shift = PackHeartShift.find(restingHRDelta: rhr, hrvDeltaPct: [:], packs: [-3, -2, -1], in: packs, cal: cal)
        XCTAssertEqual(shift?.restingHR ?? 0, 1.2, accuracy: 0.001)
        XCTAssertEqual(shift?.hrvPct, 0)
    }

    func testNothingWhenOnePackDisagreesOrTheShiftIsSmall() {
        let mixed = series { p, d in d > 21 ? (p == -2 ? -1 : 2) : 0 }
        XCTAssertNil(PackHeartShift.find(restingHRDelta: mixed, hrvDeltaPct: [:], packs: [-3, -2, -1], in: packs, cal: cal))
        let small = series { _, d in d > 21 ? 0.5 : 0 }
        XCTAssertNil(PackHeartShift.find(restingHRDelta: small, hrvDeltaPct: [:], packs: [-3, -2, -1], in: packs, cal: cal))
        XCTAssertNil(PackHeartShift.find(restingHRDelta: series { _, d in d > 21 ? 2 : 0 }, hrvDeltaPct: [:],
                                         packs: [-2, -1], in: packs, cal: cal))
    }

    func testCappedAtTwoBeats() {
        let big = series { _, d in d > 21 ? 5 : 0 }
        XCTAssertEqual(PackHeartShift.find(restingHRDelta: big, hrvDeltaPct: [:], packs: [-3, -2, -1], in: packs, cal: cal)?.restingHR, 2)
    }
}

import XCTest
@testable import HealthCore

/// H-A6: refill date, packs left, and the reminder before campus breaks.
final class PillRefillTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testLastPackRefillDateAndCount() {
        let r = PillRefill(countedFrom: date(2026, 10, 11), packs: 1, packLength: 28)
        XCTAssertEqual(r.refillBy(calendar: cal), date(2026, 11, 8))
        XCTAssertEqual(r.packsLeft(on: date(2026, 10, 28), calendar: cal), 1)
        XCTAssertEqual(r.packsLeft(on: date(2026, 11, 8), calendar: cal), 0)
        // A week ahead at 10am.
        XCTAssertEqual(r.reminder(calendar: cal), date(2026, 11, 1, 10))
    }

    func testPacksCountDownAsPacksStart() {
        let r = PillRefill(countedFrom: date(2026, 9, 13), packs: 3, packLength: 28)
        XCTAssertEqual(r.packsLeft(on: date(2026, 10, 10), calendar: cal), 3)
        XCTAssertEqual(r.packsLeft(on: date(2026, 10, 11), calendar: cal), 2)
        XCTAssertEqual(r.refillBy(calendar: cal), date(2026, 12, 6))
    }

    // Runs out over Thanksgiving (Nov 26, 2026): remind a week before the break.
    func testThanksgivingMovesTheReminderEarlier() {
        let r = PillRefill(countedFrom: date(2026, 10, 27), packs: 1, packLength: 28)
        XCTAssertEqual(r.refillBy(calendar: cal), date(2026, 11, 24))
        XCTAssertEqual(PillRefill.campusBreak(containing: date(2026, 11, 24), calendar: cal)?.start, date(2026, 11, 21))
        XCTAssertEqual(r.reminder(calendar: cal), date(2026, 11, 14, 10))
    }

    // Runs out over winter break, including the January side of it.
    func testWinterBreakMovesTheReminderEarlier() {
        let r = PillRefill(countedFrom: date(2026, 12, 6), packs: 1, packLength: 28)
        XCTAssertEqual(r.refillBy(calendar: cal), date(2027, 1, 3))
        XCTAssertEqual(r.reminder(calendar: cal), date(2026, 12, 6, 10))
        XCTAssertNil(PillRefill.campusBreak(containing: date(2027, 1, 16), calendar: cal))
        XCTAssertNil(PillRefill.campusBreak(containing: date(2026, 11, 20), calendar: cal))
    }
}

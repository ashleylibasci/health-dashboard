import XCTest
@testable import HealthCore

/// Phase 2 pill features: past packs, the missed-pill helper, bleeds and
/// mood by pack, break-week patterns and pack-day baselines.
final class PillHistoryTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// Pack starting Oct 11, 21 + 7.
    private var packs: PackCalendar { PackCalendar(start: date(2026, 10, 11), activeDays: 21, packLength: 28) }

    // MARK: Packs going back

    func testPositionCountsWholePacksBack() {
        XCTAssertEqual(packs.position(of: date(2026, 10, 28, 15), calendar: cal), .init(pack: 0, day: 18))
        XCTAssertEqual(packs.position(of: date(2026, 10, 10), calendar: cal), .init(pack: -1, day: 28))
        XCTAssertEqual(packs.position(of: date(2026, 9, 13), calendar: cal), .init(pack: -1, day: 1))
        XCTAssertEqual(packs.position(of: date(2026, 9, 12), calendar: cal), .init(pack: -2, day: 28))
        XCTAssertEqual(packs.date(pack: -1, day: 22, calendar: cal), date(2026, 10, 4))
    }

    func testFinishedPacksStartAfterTheMethodChange() {
        let now = date(2026, 10, 28, 12)
        // Changed mid-pack on Aug 20: that pack doesn't count.
        XCTAssertEqual(packs.finishedPacks(since: date(2026, 8, 20), now: now, calendar: cal), [-1])
        XCTAssertEqual(packs.finishedPacks(since: date(2026, 8, 16), now: now, calendar: cal), [-2, -1])
        XCTAssertEqual(packs.finishedPacks(since: nil, now: now, calendar: cal).count, 24)
        XCTAssertEqual(packs.finishedPacks(since: date(2026, 10, 20), now: now, calendar: cal), [])
    }
}

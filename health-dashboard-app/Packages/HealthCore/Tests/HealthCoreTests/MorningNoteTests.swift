import XCTest
@testable import HealthCore

/// Saved-ideas build (Oct 29): one morning note (D-N1).
final class MorningNoteTests: XCTestCase {
    func testWords() {
        let w = MorningNoteText.words(score: 68, label: "Take it steady", pillDay: 18, bedtime: 1430, bodyHiddenWhenLocked: true)
        XCTAssertEqual(w.title, "68 \u{00B7} Take it steady")
        XCTAssertEqual(w.body, "Pill day 18 \u{00B7} bed by \(Clock.format(1430)) tonight")
        // Previews shown on the lock screen: the pill stays out.
        let open = MorningNoteText.words(score: 68, label: "Take it steady", pillDay: 18, bedtime: 1430, bodyHiddenWhenLocked: false)
        XCTAssertFalse(open.body.contains("Pill"))
        XCTAssertFalse(open.title.contains("Pill"))
        XCTAssertEqual(open.body, "Bed by \(Clock.format(1430)) tonight")
        // Set before her sleep is in: no score.
        XCTAssertEqual(MorningNoteText.words(score: nil, label: nil, pillDay: nil, bedtime: 30, bodyHiddenWhenLocked: true).title, "Good morning")
    }

    func testFireDate() {
        let wake = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(MorningNoteText.fireDate(wake: wake, now: wake), wake.addingTimeInterval(45 * 60))
        // Sleep came in late: a minute from now, up to 3 hours after waking.
        let later = wake.addingTimeInterval(90 * 60)
        XCTAssertEqual(MorningNoteText.fireDate(wake: wake, now: later), later.addingTimeInterval(60))
        XCTAssertNil(MorningNoteText.fireDate(wake: wake, now: wake.addingTimeInterval(181 * 60)))
    }
}

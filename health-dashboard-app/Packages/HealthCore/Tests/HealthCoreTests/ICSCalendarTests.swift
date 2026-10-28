import XCTest
@testable import HealthCore

final class ICSCalendarTests: XCTestCase {
    private let chicago = TimeZone(identifier: "America/Chicago")!

    func testOneOffEventsOnly() {
        let feed = """
        BEGIN:VCALENDAR\r
        BEGIN:VEVENT\r
        UID:abc@google.com\r
        DTSTART;TZID=America/Chicago:20261104T093000\r
        SUMMARY:BIO 201 Midterm\r
        BEGIN:VALARM\r
        SUMMARY:Alarm notification\r
        END:VALARM\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:class@google.com\r
        DTSTART:20260901T100000\r
        RRULE:FREQ=WEEKLY\r
        SUMMARY:BIO 201 Lecture\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:gone@google.com\r
        DTSTART;VALUE=DATE:20261110\r
        STATUS:CANCELLED\r
        SUMMARY:Chem quiz\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        DTSTART;VALUE=DATE:20261212\r
        SUMMARY:Final exam\\, Calc\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let events = ICSCalendar.parse(feed, timeZone: chicago)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], .init(id: "abc@google.com", title: "BIO 201 Midterm", year: 2026, month: 11, day: 4, start: 570))
        XCTAssertEqual(events[1].title, "Final exam, Calc")
        XCTAssertNil(events[1].start)
        XCTAssertEqual(events[1].id, "Final exam, Calc|2026-12-12")
    }

    func testUTCTimeMovesToLocalDay() {
        let feed = "BEGIN:VEVENT\nUID:x\nDTSTART:20261105T030000Z\nSUMMARY:Night exam\nEND:VEVENT\n"
        let e = ICSCalendar.parse(feed, timeZone: chicago)[0]
        XCTAssertEqual([e.month, e.day], [11, 4])
        XCTAssertEqual(e.start, 21 * 60)
    }

    func testFoldedLines() {
        let feed = "BEGIN:VEVENT\nUID:y\nDTSTART:20261120T140000\nSUMMARY:Organic chemistry\n  final\nEND:VEVENT\n"
        XCTAssertEqual(ICSCalendar.parse(feed, timeZone: chicago).first?.title, "Organic chemistry final")
    }
}

import XCTest
@testable import HealthCore

/// H-A1: the pill pack on the calendar, which day a dose counts for, and the
/// reminder plan.
final class PillScheduleTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testPackDayCountsOnIntoLaterPacks() {
        let pack = PillPack(start: date(2026, 10, 11), activeDays: 21, packLength: 28)
        XCTAssertEqual(pack.day(on: date(2026, 10, 28, 15), calendar: cal), 18)
        XCTAssertEqual(pack.day(on: date(2026, 11, 1), calendar: cal), 22)
        XCTAssertFalse(pack.isPillDay(date(2026, 11, 1), calendar: cal))
        XCTAssertTrue(pack.isNewPackDay(date(2026, 11, 8), calendar: cal))
    }

    // Skipping the break: a start ahead means the days before it are active.
    func testStartAheadKeepsDaysActive() {
        let pack = PillPack(start: date(2026, 11, 1), activeDays: 21, packLength: 28)
        XCTAssertEqual(pack.day(on: date(2026, 10, 29), calendar: cal), 19)
        XCTAssertTrue(pack.isPillDay(date(2026, 10, 31), calendar: cal))
        XCTAssertTrue(pack.isNewPackDay(date(2026, 11, 1), calendar: cal))
    }

    func testDoseCountsForTheNearestPillTime() {
        let ninePM = 21 * 60
        XCTAssertEqual(PillDay.day(for: date(2026, 10, 28, 20, 52), pillTime: ninePM, calendar: cal), date(2026, 10, 28))
        // An hour after midnight: a late one for the evening before.
        XCTAssertEqual(PillDay.day(for: date(2026, 10, 29, 1, 0), pillTime: ninePM, calendar: cal), date(2026, 10, 28))
        // Mid-morning: early for the coming evening.
        XCTAssertEqual(PillDay.day(for: date(2026, 10, 29, 9, 30), pillTime: ninePM, calendar: cal), date(2026, 10, 29))
        // A morning pill time: 6am counts for that day, 8pm the evening before the next.
        XCTAssertEqual(PillDay.day(for: date(2026, 10, 29, 6, 0), pillTime: 8 * 60, calendar: cal), date(2026, 10, 29))
        XCTAssertEqual(PillDay.day(for: date(2026, 10, 29, 20, 30), pillTime: 8 * 60, calendar: cal), date(2026, 10, 30))
    }

    // An ordinary pill day: the reminder, then one repeat an hour later.
    func testOrdinaryDayRemindsThenRepeatsOnce() {
        let pack = PillPack(start: date(2026, 10, 11), activeDays: 21, packLength: 28)
        let plan = PillReminderPlan.reminders(pack: pack, pillTime: 21 * 60, now: date(2026, 10, 28, 12), days: 1,
                                              isTaken: { _ in false }, calendar: cal)
        XCTAssertEqual(plan.map(\.kind), [.onTime, .followUp])
        XCTAssertEqual(plan.map(\.fire), [date(2026, 10, 28, 21), date(2026, 10, 28, 22)])
        XCTAssertEqual(plan.first?.packDay, 18)
    }

    func testTakenDaysAndBreakDaysGetNothing() {
        let pack = PillPack(start: date(2026, 10, 11), activeDays: 21, packLength: 28)
        let taken = PillReminderPlan.reminders(pack: pack, pillTime: 21 * 60, now: date(2026, 10, 28, 12), days: 1,
                                               isTaken: { _ in true }, calendar: cal)
        XCTAssertTrue(taken.isEmpty)
        // Nov 1–6 are break days with no new pack the next day.
        let breakDays = PillReminderPlan.reminders(pack: pack, pillTime: 21 * 60, now: date(2026, 11, 1, 8), days: 6,
                                                   isTaken: { _ in false }, calendar: cal)
        XCTAssertTrue(breakDays.isEmpty)
    }

    // New pack: a heads-up the evening before, then the reminder and two repeats.
    func testNewPackDayIsTheLoudest() {
        let pack = PillPack(start: date(2026, 10, 11), activeDays: 21, packLength: 28)
        let plan = PillReminderPlan.reminders(pack: pack, pillTime: 21 * 60, now: date(2026, 11, 7, 8), days: 2,
                                              isTaken: { _ in false }, calendar: cal)
        XCTAssertEqual(plan.map(\.kind), [.newPackTomorrow, .onTime, .followUp, .followUp])
        XCTAssertEqual(plan.map(\.fire), [date(2026, 11, 7, 21), date(2026, 11, 8, 21), date(2026, 11, 8, 21, 30), date(2026, 11, 8, 22)])
        XCTAssertTrue(plan[1].isNewPack)
        XCTAssertFalse(plan[0].isNewPack)
    }

    // Apple's Medications reminds her at the pill time: only the repeat comes from here.
    func testAppleScheduleLeavesOnlyTheRepeat() {
        let pack = PillPack(start: date(2026, 10, 11), activeDays: 21, packLength: 28)
        let plan = PillReminderPlan.reminders(pack: pack, pillTime: 21 * 60, now: date(2026, 10, 28, 12), days: 1,
                                              isTaken: { _ in false }, skipOnTime: true, calendar: cal)
        XCTAssertEqual(plan.map(\.kind), [.followUp])
    }

    // Nov 1, 2026 is a clock-change day: still 9pm on the clock.
    func testClockChangeDayKeepsTheWallTime() {
        let pack = PillPack(start: date(2026, 10, 11), activeDays: 28, packLength: 28)
        let plan = PillReminderPlan.reminders(pack: pack, pillTime: 21 * 60, now: date(2026, 11, 1, 8), days: 1,
                                              isTaken: { _ in false }, calendar: cal)
        XCTAssertEqual(plan.first?.fire, date(2026, 11, 1, 21))
    }

    func testPastRemindersAreLeftOut() {
        let pack = PillPack(start: date(2026, 10, 11), activeDays: 21, packLength: 28)
        let plan = PillReminderPlan.reminders(pack: pack, pillTime: 21 * 60, now: date(2026, 10, 28, 21, 15), days: 1,
                                              isTaken: { _ in false }, calendar: cal)
        XCTAssertEqual(plan.map(\.kind), [.followUp])
    }
}
